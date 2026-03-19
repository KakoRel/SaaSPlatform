import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/task.dart';
import '../../../core/services/supabase_client.dart';
import '../../../core/errors/exceptions.dart';

// Kanban state
class KanbanState {
  const KanbanState({
    this.tasksByStatus = const {},
    this.isLoading = false,
    this.error,
    this.currentProjectId,
    this.isRealtimeConnected = false,
  });

  final Map<TaskStatus, List<Task>> tasksByStatus;
  final bool isLoading;
  final String? error;
  final String? currentProjectId;
  final bool isRealtimeConnected;

  KanbanState copyWith({
    Map<TaskStatus, List<Task>>? tasksByStatus,
    bool? isLoading,
    String? error,
    String? currentProjectId,
    bool? isRealtimeConnected,
    bool clearError = false,
  }) {
    return KanbanState(
      tasksByStatus: tasksByStatus ?? this.tasksByStatus,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      currentProjectId: currentProjectId ?? this.currentProjectId,
      isRealtimeConnected: isRealtimeConnected ?? this.isRealtimeConnected,
    );
  }
}

// Kanban provider
class KanbanNotifier extends StateNotifier<KanbanState> {
  KanbanNotifier(this._supabaseService) : super(const KanbanState());

  final SupabaseClientService _supabaseService;
  RealtimeChannel? _tasksChannel;
  Timer? _debounceTimer;

  Future<void> loadTasks(String projectId) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentProjectId: projectId,
    );

    try {
      await _checkProjectAccess(projectId);

      final tasks = await _fetchTasks(projectId);

      // Group tasks by status
      final tasksByStatus = <TaskStatus, List<Task>>{};
      for (final status in TaskStatus.values) {
        tasksByStatus[status] = [];
      }
      for (final task in tasks) {
        tasksByStatus[task.status]!.add(task);
      }

      // Sort by position
      for (final status in TaskStatus.values) {
        tasksByStatus[status]!.sort((a, b) => a.position.compareTo(b.position));
      }

      state = state.copyWith(
        tasksByStatus: tasksByStatus,
        isLoading: false,
      );

      _setupRealtimeSubscription(projectId);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _checkProjectAccess(String projectId) async {
    final member = await _supabaseService.fetchSingle<Map<String, dynamic>>(
      tableName: 'project_members',
      fromJson: (json) => json,
      filters: [
        QueryFilter('project_id', 'eq', projectId),
        QueryFilter('user_id', 'eq', _supabaseService.currentUserId!),
      ],
    );

    if (member == null) {
      throw const AuthorizationException('Access denied to this project');
    }
  }

  Future<List<Task>> _fetchTasks(String projectId) async {
    final tasksData = await _supabaseService.fetchList<Map<String, dynamic>>(
      tableName: 'project_tasks',
      fromJson: (json) => json,
      filters: [
        QueryFilter('project_id', 'eq', projectId),
      ],
      orderBy: [const Ordering('position', ascending: true)],
    );

    return tasksData.map((data) => Task.fromJson(data)).toList();
  }

  void _setupRealtimeSubscription(String projectId) {
    _tasksChannel?.unsubscribe();

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

  void _handleRealtimeEvent(PostgresChangePayload payload) {
    final eventType = payload.eventType;
    final newRecord = payload.newRecord;
    final oldRecord = payload.oldRecord;

    // Deep copy the map of lists
    final updated = <TaskStatus, List<Task>>{};
    for (final entry in state.tasksByStatus.entries) {
      updated[entry.key] = List<Task>.from(entry.value);
    }

    if (eventType == PostgresChangeEvent.insert && newRecord.isNotEmpty) {
      final task = Task.fromJson(newRecord);
      updated[task.status]?.add(task);
      updated[task.status]?.sort((a, b) => a.position.compareTo(b.position));
    } else if (eventType == PostgresChangeEvent.update && newRecord.isNotEmpty) {
      final task = Task.fromJson(newRecord);
      for (final status in TaskStatus.values) {
        updated[status]?.removeWhere((t) => t.id == task.id);
      }
      updated[task.status]?.add(task);
      updated[task.status]?.sort((a, b) => a.position.compareTo(b.position));
    } else if (eventType == PostgresChangeEvent.delete && oldRecord.isNotEmpty) {
      final taskId = oldRecord['id'] as String?;
      if (taskId != null) {
        for (final status in TaskStatus.values) {
          updated[status]?.removeWhere((t) => t.id == taskId);
        }
      }
    }

    state = state.copyWith(tasksByStatus: updated);
  }

  Future<void> createTask({
    required String title,
    String? description,
    String? assigneeId,
    TaskPriority priority = TaskPriority.medium,
  }) async {
    if (state.currentProjectId == null) return;

    try {
      await _supabaseService.insert<Map<String, dynamic>>(
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
          'status': newStatus.toDbValue(),
          'position': newPosition,
        },
        fromJson: (json) => json,
      );
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
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteTask(String taskId) async {
    try {
      await _supabaseService.delete(tableName: 'tasks', id: taskId);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  int _getNextPosition(TaskStatus status) {
    final tasks = state.tasksByStatus[status] ?? [];
    if (tasks.isEmpty) return 0;
    return tasks.last.position + 1;
  }

  Future<void> handleDragDrop({
    required String taskId,
    required TaskStatus fromStatus,
    required TaskStatus toStatus,
    required int fromIndex,
    required int toIndex,
  }) async {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      // Optimistic update
      final updated = <TaskStatus, List<Task>>{};
      for (final entry in state.tasksByStatus.entries) {
        updated[entry.key] = List<Task>.from(entry.value);
      }

      final fromTasks = updated[fromStatus]!;
      if (fromIndex >= fromTasks.length) return;

      final task = fromTasks.removeAt(fromIndex);

      if (fromStatus == toStatus) {
        fromTasks.insert(toIndex, task.copyWith(position: toIndex));
      } else {
        final toTasks = updated[toStatus]!;
        toTasks.insert(toIndex, task.copyWith(status: toStatus, position: toIndex));
      }

      state = state.copyWith(tasksByStatus: updated);

      // Persist to DB
      await updateTaskStatus(
        taskId: taskId,
        newStatus: toStatus,
        newPosition: toIndex,
      );
    });
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  @override
  void dispose() {
    _tasksChannel?.unsubscribe();
    _debounceTimer?.cancel();
    super.dispose();
  }
}

// Providers
final kanbanProvider = StateNotifierProvider<KanbanNotifier, KanbanState>((ref) {
  final supabaseService = SupabaseClientService.instance;
  return KanbanNotifier(supabaseService);
});
