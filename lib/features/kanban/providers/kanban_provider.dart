import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban_board/kanban_board.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/task.dart';
import '../../../core/services/supabase_client.dart';
import '../../../core/errors/exceptions.dart';
import '../../auth/providers/auth_provider.dart';

// Kanban state
@freezed
class KanbanState with _$KanbanState {
  const factory KanbanState({
    @Default({}) Map<TaskStatus, List<Task>> tasksByStatus,
    @Default(false) bool isLoading,
    String? error,
    String? currentProjectId,
    @Default(false) bool isRealtimeConnected,
  }) = _KanbanState;
}

// Kanban provider
class KanbanNotifier extends StateNotifier<KanbanState> {
  KanbanNotifier(this._supabaseService, this._authProvider) : super(const KanbanState()) {
    _initializeRealtime();
  }

  final SupabaseClientService _supabaseService;
  final AuthNotifier _authProvider;
  RealtimeChannel? _tasksChannel;
  Timer? _debounceTimer;

  void _initializeRealtime() {
    // Will be called when project is set
  }

  Future<void> loadTasks(String projectId) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      currentProjectId: projectId,
    );

    try {
      // Check if user has access to this project
      await _checkProjectAccess(projectId);

      // Load tasks
      final tasks = await _fetchTasks(projectId);
      
      // Group tasks by status
      final tasksByStatus = <TaskStatus, List<Task>>{};
      for (final status in TaskStatus.values) {
        tasksByStatus[status] = [];
      }

      for (final task in tasks) {
        tasksByStatus[task.status]!.add(task);
      }

      // Sort tasks by position within each status
      for (final status in TaskStatus.values) {
        tasksByStatus[status]!.sort((a, b) => a.position.compareTo(b.position));
      }

      state = state.copyWith(
        tasksByStatus: tasksByStatus,
        isLoading: false,
      );

      // Setup realtime subscription
      _setupRealtimeSubscription(projectId);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _checkProjectAccess(String projectId) async {
    try {
      final member = await _supabaseService.fetchSingle<Map<String, dynamic>>(
        tableName: 'project_members',
        fromJson: (json) => json,
        filters: [
          Filter('project_id', 'eq', projectId),
          Filter('user_id', 'eq', _supabaseService.currentUserId!),
        ],
      );

      if (member == null) {
        throw const AuthorizationException('Access denied to this project');
      }
    } catch (e) {
      throw AuthorizationException('Failed to check project access: ${e.toString()}');
    }
  }

  Future<List<Task>> _fetchTasks(String projectId) async {
    try {
      final tasksData = await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'project_tasks', // Using the view we created
        fromJson: (json) => json,
        filters: [
          Filter('project_id', 'eq', projectId),
        ],
        orderBy: [Ordering('position', ascending: true)],
      );

      return tasksData.map((taskData) => Task.fromJson(taskData)).toList();
    } catch (e) {
      throw ServerException('Failed to fetch tasks: ${e.toString()}');
    }
  }

  void _setupRealtimeSubscription(String projectId) {
    // Cancel previous subscription
    _tasksChannel?.unsubscribe();

    // Setup new subscription
    _tasksChannel = _supabaseService.subscribeToTable(
      tableName: 'tasks',
      channelId: 'tasks_$projectId',
      callback: (payload) {
        _handleRealtimeEvent(payload);
      },
    );

    _tasksChannel?.subscribe();

    state = state.copyWith(isRealtimeConnected: true);
  }

  void _handleRealtimeEvent(RealtimePayload payload) {
    final eventType = payload.eventType;
    final record = payload.newRecord ?? payload.oldRecord;

    if (record == null) return;

    final task = Task.fromJson(record as Map<String, dynamic>);
    final currentTasksByStatus = Map<TaskStatus, List<Task>>.from(state.tasksByStatus);

    switch (eventType) {
      case PostgresChangeEvent.insert:
        currentTasksByStatus[task.status]!.add(task);
        currentTasksByStatus[task.status]!.sort((a, b) => a.position.compareTo(b.position));
        break;

      case PostgresChangeEvent.update:
        // Remove from old status if changed
        for (final status in TaskStatus.values) {
          currentTasksByStatus[status]!.removeWhere((t) => t.id == task.id);
        }
        // Add to new status
        currentTasksByStatus[task.status]!.add(task);
        currentTasksByStatus[task.status]!.sort((a, b) => a.position.compareTo(b.position));
        break;

      case PostgresChangeEvent.delete:
        for (final status in TaskStatus.values) {
          currentTasksByStatus[status]!.removeWhere((t) => t.id == task.id);
        }
        break;
    }

    state = state.copyWith(tasksByStatus: currentTasksByStatus);
  }

  Future<void> createTask({
    required String title,
    String? description,
    String? assigneeId,
    TaskPriority priority = TaskPriority.medium,
  }) async {
    if (state.currentProjectId == null) return;

    try {
      final newTask = await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'tasks',
        data: {
          'project_id': state.currentProjectId,
          'title': title,
          'description': description,
          'assignee_id': assigneeId,
          'creator_id': _supabaseService.currentUserId!,
          'priority': priority.name,
          'position': _getNextPosition(TaskStatus.todo),
        },
        fromJson: (json) => json,
      );

      // Realtime will handle the update
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateTaskStatus({
    required String taskId,
    required TaskStatus newStatus,
    required int newPosition,
  }) async {
    try {
      await _supabaseService.update<Map<String, dynamic>>(
        tableName: 'tasks',
        id: taskId,
        data: {
          'status': newStatus.name,
          'position': newPosition,
        },
        fromJson: (json) => json,
      );

      // Realtime will handle the update
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateTask({
    required String taskId,
    String? title,
    String? description,
    String? assigneeId,
    TaskPriority? priority,
    DateTime? dueDate,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      if (title != null) updateData['title'] = title;
      if (description != null) updateData['description'] = description;
      if (assigneeId != null) updateData['assignee_id'] = assigneeId;
      if (priority != null) updateData['priority'] = priority.name;
      if (dueDate != null) updateData['due_date'] = dueDate.toIso8601String();

      await _supabaseService.update<Map<String, dynamic>>(
        tableName: 'tasks',
        id: taskId,
        data: updateData,
        fromJson: (json) => json,
      );

      // Realtime will handle the update
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteTask(String taskId) async {
    try {
      await _supabaseService.delete(
        tableName: 'tasks',
        id: taskId,
      );

      // Realtime will handle the update
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  int _getNextPosition(TaskStatus status) {
    final tasks = state.tasksByStatus[status] ?? [];
    if (tasks.isEmpty) return 0;
    return tasks.last.position + 1;
  }

  // Drag and drop handling
  Future<void> handleDragDrop({
    required String taskId,
    required TaskStatus fromStatus,
    required TaskStatus toStatus,
    required int fromIndex,
    required int toIndex,
  }) async {
    // Debounce rapid drag operations
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      await _performDragDrop(
        taskId: taskId,
        fromStatus: fromStatus,
        toStatus: toStatus,
        fromIndex: fromIndex,
        toIndex: toIndex,
      );
    });
  }

  Future<void> _performDragDrop({
    required String taskId,
    required TaskStatus fromStatus,
    required TaskStatus toStatus,
    required int fromIndex,
    required int toIndex,
  }) async {
    final currentTasksByStatus = Map<TaskStatus, List<Task>>.from(state.tasksByStatus);
    final fromTasks = List<Task>.from(currentTasksByStatus[fromStatus]!);
    final toTasks = List<Task>.from(currentTasksByStatus[toStatus]!);

    // Remove task from original position
    final task = fromTasks.removeAt(fromIndex);

    // Insert task in new position
    toTasks.insert(toIndex, task);

    // Update positions for all affected tasks
    await _updateTaskPositions(fromStatus, fromTasks);
    if (fromStatus != toStatus) {
      await _updateTaskPositions(toStatus, toTasks);
    }

    // Update task status if changed
    if (fromStatus != toStatus) {
      await updateTaskStatus(
        taskId: taskId,
        newStatus: toStatus,
        newPosition: toIndex,
      );
    } else {
      await updateTaskStatus(
        taskId: taskId,
        newStatus: toStatus,
        newPosition: toIndex,
      );
    }
  }

  Future<void> _updateTaskPositions(TaskStatus status, List<Task> tasks) async {
    for (int i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (task.position != i) {
        await _supabaseService.update<Map<String, dynamic>>(
          tableName: 'tasks',
          id: task.id,
          data: {'position': i},
          fromJson: (json) => json,
        );
      }
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void dispose() {
    _tasksChannel?.unsubscribe();
    _debounceTimer?.cancel();
    super.dispose();
  }
}

// Providers
final kanbanProvider = StateNotifierProvider<KanbanNotifier, KanbanState>((ref) {
  final supabaseService = SupabaseClientService.instance;
  final authProvider = ref.watch(authProvider.notifier);
  return KanbanNotifier(supabaseService, authProvider);
});

// Kanban board data provider for the UI component
final kanbanBoardDataProvider = Provider<KanbanBoardData>((ref) {
  final kanbanState = ref.watch(kanbanProvider);
  
  final columns = kanbanState.tasksByStatus.entries.map((entry) {
    final status = entry.key;
    final tasks = entry.value;
    
    return KanbanBoardColumn(
      id: status.name,
      title: _getStatusLabel(status),
      items: tasks.map((task) => KanbanBoardItem(
        id: task.id,
        child: TaskCard(task: task),
      )).toList(),
    );
  }).toList();

  return KanbanBoardData(
    columns: columns,
    onItemReorder: _handleItemReorder(ref),
    onItemDrop: _handleItemDrop(ref),
  );
});

String _getStatusLabel(TaskStatus status) {
  switch (status) {
    case TaskStatus.todo:
      return 'To Do';
    case TaskStatus.inProgress:
      return 'In Progress';
    case TaskStatus.review:
      return 'Review';
    case TaskStatus.done:
      return 'Done';
  }
}

Function(String, String, int, int) _handleItemReorder(Ref ref) {
  return (itemId, fromColumnId, fromIndex, toIndex) {
    // Handle reordering within the same column
    final kanbanNotifier = ref.read(kanbanProvider.notifier);
    final fromStatus = TaskStatus.values.firstWhere((s) => s.name == fromColumnId);
    
    kanbanNotifier.handleDragDrop(
      taskId: itemId,
      fromStatus: fromStatus,
      toStatus: fromStatus,
      fromIndex: fromIndex,
      toIndex: toIndex,
    );
  };
}

Function(String, String, int, int) _handleItemDrop(Ref ref) {
  return (itemId, fromColumnId, fromIndex, toIndex) {
    // Handle dropping to a different column
    final kanbanNotifier = ref.read(kanbanProvider.notifier);
    final fromStatus = TaskStatus.values.firstWhere((s) => s.name == fromColumnId);
    final toStatus = TaskStatus.values.firstWhere((s) => s.name == fromColumnId);
    
    kanbanNotifier.handleDragDrop(
      taskId: itemId,
      fromStatus: fromStatus,
      toStatus: toStatus,
      fromIndex: fromIndex,
      toIndex: toIndex,
    );
  };
}

// Task card widget (simplified)
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (task.description != null) ...[
              const SizedBox(height: 4),
              Text(
                task.description!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _PriorityChip(priority: task.priority),
                const Spacer(),
                if (task.assignee != null)
                  CircleAvatar(
                    radius: 12,
                    backgroundImage: NetworkImage(task.assignee!.avatarUrl ?? ''),
                    child: task.assignee!.avatarUrl == null
                        ? Text(
                            task.assignee!.fullName[0].toUpperCase(),
                            style: const TextStyle(fontSize: 10),
                          )
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      TaskPriority.low => Colors.green,
      TaskPriority.medium => Colors.blue,
      TaskPriority.high => Colors.orange,
      TaskPriority.urgent => Colors.red,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        priority.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
