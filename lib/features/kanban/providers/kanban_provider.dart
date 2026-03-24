import 'dart:async';

import 'package:flutter/foundation.dart';
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
    this.currentBoardId,
    this.activeSprintId,
    this.isRealtimeConnected = false,
    this.isDemoData = false,
    this.demoMessage,
  });

  final Map<TaskStatus, List<Task>> tasksByStatus;
  final bool isLoading;
  final String? error;
  final String? currentProjectId;
  final String? currentBoardId;
  final String? activeSprintId;
  final bool isRealtimeConnected;
  final bool isDemoData;
  final String? demoMessage;

  KanbanState copyWith({
    Map<TaskStatus, List<Task>>? tasksByStatus,
    bool? isLoading,
    String? error,
    String? currentProjectId,
    String? currentBoardId,
    String? activeSprintId,
    bool? isRealtimeConnected,
    bool clearError = false,
    bool? isDemoData,
    String? demoMessage,
    bool clearDemoMessage = false,
  }) {
    return KanbanState(
      tasksByStatus: tasksByStatus ?? this.tasksByStatus,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      currentProjectId: currentProjectId ?? this.currentProjectId,
      currentBoardId: currentBoardId ?? this.currentBoardId,
      activeSprintId: activeSprintId ?? this.activeSprintId,
      isRealtimeConnected: isRealtimeConnected ?? this.isRealtimeConnected,
      isDemoData: isDemoData ?? this.isDemoData,
      demoMessage: clearDemoMessage ? null : (demoMessage ?? this.demoMessage),
    );
  }
}

// Kanban provider
class KanbanNotifier extends StateNotifier<KanbanState> {
  KanbanNotifier(this._supabaseService) : super(const KanbanState());

  final SupabaseClientService _supabaseService;
  RealtimeChannel? _tasksChannel;
  Timer? _debounceTimer;
  Timer? _realtimeReloadDebounceTimer;
  DateTime? _lastRealtimeReloadAt;

  Future<void> loadTasks(
    String projectId, {
    String? boardId,
    bool fromRealtime = false,
  }) async {
    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(projectId);

    if (!isUuid) {
      state = state.copyWith(currentProjectId: projectId);
      _activateDemoMode(
        message: 'Используется демонстрационный режим. Подключите реальный проект, чтобы увидеть свои задачи.',
      );
      return;
    }

    // Guard against rapid duplicate reloads for the same board/project.
    if (state.isLoading &&
        state.currentProjectId == projectId &&
        state.currentBoardId == boardId) {
      return;
    }
    if (fromRealtime && _lastRealtimeReloadAt != null) {
      final since = DateTime.now().difference(_lastRealtimeReloadAt!);
      if (since.inMilliseconds < 1800) {
        return;
      }
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentProjectId: projectId,
      currentBoardId: boardId,
      clearDemoMessage: true,
    );

    if (!_supabaseService.isInitialized) {
      _activateDemoMode(
        message: 'Supabase не настроен. Показаны демо-данные Kanban доски.',
      );
      return;
    }

    try {
      await _checkProjectAccess(projectId);

      final tasks = await _fetchTasks(projectId, boardId: boardId);
      final activeSprintId = await _getActiveSprintId(projectId);

      final tasksByStatus = <TaskStatus, List<Task>>{
        for (final status in TaskStatus.values) status: [],
      };

      for (final task in tasks.where(
        (t) => t.sprintId == activeSprintId || t.issueType == TaskIssueType.epic,
      )) {
        tasksByStatus[task.status]!.add(task);
      }

      for (final status in TaskStatus.values) {
        tasksByStatus[status]!.sort((a, b) => a.position.compareTo(b.position));
      }

      state = state.copyWith(
        tasksByStatus: tasksByStatus,
        isLoading: false,
        activeSprintId: activeSprintId,
        isDemoData: false,
      );
      if (fromRealtime) {
        _lastRealtimeReloadAt = DateTime.now();
      }

      _setupRealtimeSubscription(projectId, boardId: boardId);
    } on AuthorizationException {
      _activateDemoMode(
        message: 'Пользователь не является участником проекта. Показаны демо-данные.',
      );
    } on ServerException catch (e) {
      if (e.message.contains('not initialized')) {
        _activateDemoMode(
          message: 'Supabase клиент недоступен. Показаны демо-данные.',
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _checkProjectAccess(String projectId) async {
    final userId = _supabaseService.currentUserId;
    if (userId == null) {
      throw const AuthorizationException('User not authenticated');
    }

    final member = await _supabaseService.fetchSingle<Map<String, dynamic>>(
      tableName: 'project_members',
      fromJson: (json) => json,
      filters: [
        QueryFilter('project_id', 'eq', projectId),
        QueryFilter('user_id', 'eq', userId),
      ],
    );

    if (member == null) {
      throw const AuthorizationException('Access denied to this project');
    }
  }

  Future<List<Task>> _fetchTasks(String projectId, {String? boardId}) async {
    List<Map<String, dynamic>> tasksData;
    try {
      // Use the view so `Task.fromJson()` receives joined fields:
      // assignee_name/assignee_email and creator_name/creator_email.
      tasksData = await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'project_tasks',
        fromJson: (json) => json,
        filters: [
          QueryFilter('project_id', 'eq', projectId),
          if (boardId != null) QueryFilter('board_id', 'eq', boardId),
        ],
        orderBy: [const Ordering('position', ascending: true)],
      );
    } catch (e) {
      final message = e.toString().toLowerCase();
      // Backward-compatibility for servers where `project_tasks` view is outdated
      // and doesn't contain `board_id` yet.
      if (message.contains('project_tasks.board_id') || message.contains('column board_id')) {
        tasksData = await _supabaseService.fetchList<Map<String, dynamic>>(
          tableName: 'tasks',
          fromJson: (json) => json,
          filters: [
            QueryFilter('project_id', 'eq', projectId),
            if (boardId != null) QueryFilter('board_id', 'eq', boardId),
          ],
          orderBy: [const Ordering('position', ascending: true)],
        );
      } else {
        rethrow;
      }
    }

    // In UI, null boardId means "Основная доска" (tasks without board_id).
    if (boardId == null) {
      tasksData = tasksData.where((row) => row['board_id'] == null).toList();
    }

    final tasks = tasksData.map(Task.fromJson).toList();

    assert(() {
      final mismatched = tasks
          .where((t) => t.assigneeId != null && t.assignee == null)
          .length;
      debugPrint(
        'Kanban loadTasks($projectId): total=${tasks.length}, assigneeId!=null & assignee==null=$mismatched',
      );
      return true;
    }());

    return tasks;
  }

  Future<List<Map<String, dynamic>>> getProjectSprints(String projectId) async {
    try {
      return await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'sprints',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
        orderBy: [const Ordering('created_at', ascending: false)],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<Map<String, dynamic>?> createSprint({
    required String projectId,
    required String name,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final now = DateTime.now();
      final resolvedStart = startDate ?? now;
      final resolvedEnd = endDate ?? resolvedStart.add(const Duration(days: 14));
      return await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'sprints',
        fromJson: (json) => json,
        data: {
          'project_id': projectId,
          'name': name,
          'start_date': resolvedStart.toIso8601String(),
          'end_date': resolvedEnd.toIso8601String(),
          'status': 'planned',
          'is_active': false,
          'created_by': _supabaseService.currentUserId,
        },
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<bool> startSprint({
    required String projectId,
    required String sprintId,
  }) async {
    try {
      final sprints = await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'sprints',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
      );

      for (final sprint in sprints) {
        final id = sprint['id'] as String?;
        if (id == null) continue;
        final now = DateTime.now();
        final rawStart = sprint['start_date']?.toString();
        final rawEnd = sprint['end_date']?.toString();
        final currentStart = DateTime.tryParse(rawStart ?? '');
        final currentEnd = DateTime.tryParse(rawEnd ?? '');
        final isTarget = id == sprintId;
        final data = <String, dynamic>{
          'is_active': isTarget,
          'status': isTarget ? 'active' : sprint['status'],
        };
        if (isTarget && currentStart == null) {
          data['start_date'] = now.toIso8601String();
        }
        if (isTarget && currentEnd == null) {
          data['end_date'] = now.add(const Duration(days: 14)).toIso8601String();
        }
        await _supabaseService.update<Map<String, dynamic>>(
          tableName: 'sprints',
          id: id,
          fromJson: (json) => json,
          data: data,
        );
      }

      state = state.copyWith(activeSprintId: sprintId);
      if (state.currentProjectId != null) {
        await loadTasks(state.currentProjectId!, boardId: state.currentBoardId);
      }
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> completeSprint({
    required String sprintId,
  }) async {
    try {
      await _supabaseService.update<Map<String, dynamic>>(
        tableName: 'sprints',
        id: sprintId,
        fromJson: (json) => json,
        data: {
          'is_active': false,
          'status': 'completed',
          'end_date': DateTime.now().toIso8601String(),
        },
      );

      if (state.activeSprintId == sprintId) {
        state = state.copyWith(activeSprintId: null);
      }
      if (state.currentProjectId != null) {
        await loadTasks(state.currentProjectId!, boardId: state.currentBoardId);
      }
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<List<Task>> getBacklogTasks({
    required String projectId,
    String? boardId,
  }) async {
    final tasks = await _fetchTasks(projectId, boardId: boardId);
    return tasks.where((task) => task.sprintId == null).toList();
  }

  Future<List<Task>> getSprintTasks({
    required String projectId,
    required String sprintId,
    String? boardId,
  }) async {
    final tasks = await _fetchTasks(projectId, boardId: boardId);
    return tasks.where((task) => task.sprintId == sprintId).toList();
  }

  Future<List<Task>> getProjectEpics({
    required String projectId,
    String? boardId,
  }) async {
    final tasks = await _fetchTasks(projectId, boardId: boardId);
    return tasks.where((task) => task.issueType == TaskIssueType.epic).toList();
  }

  Future<List<Task>> getAllProjectEpics({
    required String projectId,
  }) async {
    try {
      final rows = await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'project_tasks',
        fromJson: (json) => json,
        filters: [
          QueryFilter('project_id', 'eq', projectId),
          const QueryFilter('issue_type', 'eq', 'epic'),
        ],
        orderBy: [const Ordering('position', ascending: true)],
      );
      return rows.map(Task.fromJson).toList();
    } catch (_) {
      final rows = await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'tasks',
        fromJson: (json) => json,
        filters: [
          QueryFilter('project_id', 'eq', projectId),
          const QueryFilter('issue_type', 'eq', 'epic'),
        ],
        orderBy: [const Ordering('position', ascending: true)],
      );
      return rows.map(Task.fromJson).toList();
    }
  }

  Future<void> moveTaskToSprint({
    required String taskId,
    String? sprintId,
  }) async {
    try {
      await _supabaseService.update<Map<String, dynamic>>(
        tableName: 'tasks',
        id: taskId,
        data: {'sprint_id': sprintId},
        fromJson: (json) => json,
      );
      if (state.currentProjectId != null) {
        await loadTasks(state.currentProjectId!, boardId: state.currentBoardId);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<List<Map<String, dynamic>>> getProjectPages(String projectId) async {
    try {
      return await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'project_pages',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
        orderBy: [const Ordering('updated_at', ascending: false)],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<Map<String, dynamic>?> createProjectPage({
    required String projectId,
    required String title,
    required String content,
  }) async {
    try {
      return await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'project_pages',
        fromJson: (json) => json,
        data: {
          'project_id': projectId,
          'title': title,
          'content': content,
          'created_by': _supabaseService.currentUserId,
          'updated_by': _supabaseService.currentUserId,
        },
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateProjectPage({
    required String id,
    required String title,
    required String content,
  }) async {
    try {
      return await _supabaseService.update<Map<String, dynamic>>(
        tableName: 'project_pages',
        id: id,
        fromJson: (json) => json,
        data: {
          'title': title,
          'content': content,
          'updated_by': _supabaseService.currentUserId,
        },
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<void> deleteProjectPage(String id) async {
    try {
      await _supabaseService.delete(tableName: 'project_pages', id: id);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<List<Map<String, dynamic>>> getProjectForms(String projectId) async {
    try {
      return await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'project_forms',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
        orderBy: [const Ordering('updated_at', ascending: false)],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<Map<String, dynamic>?> createProjectForm({
    required String projectId,
    required String title,
    String? description,
    List<Map<String, dynamic>> fields = const [],
    Map<String, dynamic> issueDefaults = const {},
  }) async {
    try {
      return await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'project_forms',
        fromJson: (json) => json,
        data: {
          'project_id': projectId,
          'title': title,
          'description': description,
          'fields': fields,
          'issue_defaults': issueDefaults,
          'created_by': _supabaseService.currentUserId,
          'updated_by': _supabaseService.currentUserId,
        },
      );
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('issue_defaults') || message.contains('project_form_submissions')) {
        try {
          return await _supabaseService.insert<Map<String, dynamic>>(
            tableName: 'project_forms',
            fromJson: (json) => json,
            data: {
              'project_id': projectId,
              'title': title,
              'description': description,
              'fields': fields,
              'created_by': _supabaseService.currentUserId,
              'updated_by': _supabaseService.currentUserId,
            },
          );
        } catch (_) {}
      }
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateProjectForm({
    required String id,
    required String title,
    String? description,
    List<Map<String, dynamic>>? fields,
    Map<String, dynamic>? issueDefaults,
    bool? isActive,
  }) async {
    try {
      final data = <String, dynamic>{
        'title': title,
        'description': description,
        'updated_by': _supabaseService.currentUserId,
      };
      if (fields != null) data['fields'] = fields;
      if (issueDefaults != null) data['issue_defaults'] = issueDefaults;
      if (isActive != null) data['is_active'] = isActive;
      return await _supabaseService.update<Map<String, dynamic>>(
        tableName: 'project_forms',
        id: id,
        fromJson: (json) => json,
        data: data,
      );
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('issue_defaults')) {
        final fallbackData = <String, dynamic>{
          'title': title,
          'description': description,
          'updated_by': _supabaseService.currentUserId,
        };
        if (fields != null) fallbackData['fields'] = fields;
        if (isActive != null) fallbackData['is_active'] = isActive;
        try {
          return await _supabaseService.update<Map<String, dynamic>>(
            tableName: 'project_forms',
            id: id,
            fromJson: (json) => json,
            data: fallbackData,
          );
        } catch (_) {}
      }
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<void> deleteProjectForm(String id) async {
    try {
      await _supabaseService.delete(tableName: 'project_forms', id: id);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<Map<String, dynamic>?> submitProjectForm({
    required String projectId,
    required String formId,
    required Map<String, dynamic> answers,
    Map<String, dynamic> issueDefaults = const {},
    String? boardId,
    String? sprintId,
  }) async {
    try {
      final issueTypeRaw = issueDefaults['issue_type']?.toString();
      final priorityRaw = issueDefaults['priority']?.toString();
      final assigneeRaw = issueDefaults['assignee_id']?.toString();
      final boardRaw = issueDefaults['board_id']?.toString();
      final sprintRaw = issueDefaults['sprint_id']?.toString();

      final defaultIssueType = TaskIssueType.values.any((t) => t.name == issueTypeRaw)
          ? issueTypeRaw!
          : TaskIssueType.task.name;
      final defaultPriority = TaskPriority.values.any((p) => p.name == priorityRaw)
          ? priorityRaw!
          : TaskPriority.medium.name;

      // Validate references belong to the same project; otherwise safely ignore.
      final defaultBoardId = await _recordBelongsToProject(
        tableName: 'boards',
        recordId: boardRaw,
        projectId: projectId,
      )
          ? boardRaw
          : null;
      final defaultSprintId = await _recordBelongsToProject(
        tableName: 'sprints',
        recordId: sprintRaw,
        projectId: projectId,
      )
          ? sprintRaw
          : null;
      final defaultAssigneeId = await _isProjectMember(
        projectId: projectId,
        userId: assigneeRaw,
      )
          ? assigneeRaw
          : null;

      final taskTitle = (answers['title']?.toString().trim().isNotEmpty ?? false)
          ? answers['title'].toString().trim()
          : 'Запрос из формы';
      final taskDescription = answers.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');

      final createdTask = await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'tasks',
        fromJson: (json) => json,
        data: {
          'project_id': projectId,
          'title': taskTitle,
          'description': taskDescription,
          'assignee_id': defaultAssigneeId,
          'creator_id': _supabaseService.currentUserId,
          'priority': defaultPriority,
          'issue_type': defaultIssueType,
          'status': TaskStatus.todo.toDbValue(),
          'board_id': defaultBoardId ?? boardId ?? state.currentBoardId,
          'sprint_id': defaultSprintId ?? sprintId ?? state.activeSprintId,
          'position': _getNextPosition(TaskStatus.todo),
        },
      );

      try {
        return await _supabaseService.insert<Map<String, dynamic>>(
          tableName: 'project_form_submissions',
          fromJson: (json) => json,
          data: {
            'project_id': projectId,
            'form_id': formId,
            'submitted_by': _supabaseService.currentUserId,
            'answers': answers,
            'created_task_id': createdTask['id'],
          },
        );
      } catch (_) {
        // Backward compatibility if submissions table isn't migrated yet.
        return createdTask;
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<bool> _recordBelongsToProject({
    required String tableName,
    required String? recordId,
    required String projectId,
  }) async {
    if (recordId == null || recordId.isEmpty) return false;
    try {
      final row = await _supabaseService.fetchSingle<Map<String, dynamic>>(
        tableName: tableName,
        fromJson: (json) => json,
        filters: [
          QueryFilter('id', 'eq', recordId),
          QueryFilter('project_id', 'eq', projectId),
        ],
      );
      return row != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isProjectMember({
    required String projectId,
    required String? userId,
  }) async {
    if (userId == null || userId.isEmpty) return false;
    try {
      final row = await _supabaseService.fetchSingle<Map<String, dynamic>>(
        tableName: 'project_members',
        fromJson: (json) => json,
        filters: [
          QueryFilter('project_id', 'eq', projectId),
          QueryFilter('user_id', 'eq', userId),
        ],
      );
      return row != null;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _getActiveSprintId(String projectId) async {
    try {
      final sprints = await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'sprints',
        fromJson: (json) => json,
        filters: [
          QueryFilter('project_id', 'eq', projectId),
          const QueryFilter('is_active', 'eq', true),
        ],
        orderBy: [const Ordering('start_date', ascending: false)],
      );
      if (sprints.isEmpty) return null;
      return sprints.first['id'] as String?;
    } catch (_) {
      // Keep backward compatibility if migration is not applied yet.
      return null;
    }
  }

  Future<List<Task>> getProjectTasksForTimeline(String projectId) async {
    try {
      final tasksData = await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'project_tasks',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
        orderBy: [const Ordering('position', ascending: true)],
      );
      return tasksData.map(Task.fromJson).toList();
    } catch (_) {
      final tasksData = await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'tasks',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
        orderBy: [const Ordering('position', ascending: true)],
      );
      return tasksData.map(Task.fromJson).toList();
    }
  }

  void _setupRealtimeSubscription(String projectId, {String? boardId}) {
    _tasksChannel?.unsubscribe();

    if (state.isDemoData) {
      return;
    }

    _tasksChannel = _supabaseService.subscribeToTable(
      tableName: 'tasks',
      channelId: 'kanban_tasks_${projectId}_${boardId ?? 'main'}',
      callback: (payload) async {
        final currentProjectId = state.currentProjectId;
        if (currentProjectId == null || currentProjectId != projectId) return;

        final record = (payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord)
            as Map<String, dynamic>?;
        if (record == null || record.isEmpty) return;

        final recordProjectId = record['project_id']?.toString();
        if (recordProjectId != currentProjectId) return;

        final recordBoardId = record['board_id']?.toString();
        final currentBoardId = state.currentBoardId;
        if (currentBoardId == null) {
          if (recordBoardId != null) return;
        } else if (recordBoardId != currentBoardId) {
          return;
        }

        final taskId = record['id']?.toString();
        if (taskId == null || taskId.isEmpty) return;

        if (payload.eventType == PostgresChangeEvent.delete) {
          _removeTaskFromState(taskId);
          return;
        }

        final task = await _fetchTaskById(taskId, projectId: currentProjectId);
        if (task == null) {
          _removeTaskFromState(taskId);
          return;
        }

        _upsertTaskInState(task);
      },
    )..subscribe();

    state = state.copyWith(isRealtimeConnected: true);
  }

  Future<Task?> _fetchTaskById(
    String taskId, {
    required String projectId,
  }) async {
    try {
      final row = await _supabaseService.fetchSingle<Map<String, dynamic>>(
        tableName: 'project_tasks',
        fromJson: (json) => json,
        filters: [
          QueryFilter('id', 'eq', taskId),
          QueryFilter('project_id', 'eq', projectId),
        ],
      );
      if (row != null) {
        return Task.fromJson(row);
      }
    } catch (_) {
      // Fallback below for older DBs without a full project_tasks view.
    }

    try {
      final row = await _supabaseService.fetchSingle<Map<String, dynamic>>(
        tableName: 'tasks',
        fromJson: (json) => json,
        filters: [
          QueryFilter('id', 'eq', taskId),
          QueryFilter('project_id', 'eq', projectId),
        ],
      );
      if (row != null) {
        return Task.fromJson(row);
      }
    } catch (_) {
      // no-op
    }
    return null;
  }

  bool _isTaskVisibleInBoard(Task task) {
    final currentBoardId = state.currentBoardId;
    if (currentBoardId == null) {
      if (task.boardId != null) return false;
    } else if (task.boardId != currentBoardId) {
      return false;
    }

    if (task.issueType == TaskIssueType.epic) return true;
    return task.sprintId == state.activeSprintId;
  }

  void _removeTaskFromState(String taskId) {
    final updated = <TaskStatus, List<Task>>{};
    for (final entry in state.tasksByStatus.entries) {
      updated[entry.key] = entry.value.where((task) => task.id != taskId).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
    }
    state = state.copyWith(tasksByStatus: updated);
  }

  void _upsertTaskInState(Task task) {
    final updated = <TaskStatus, List<Task>>{};
    for (final status in TaskStatus.values) {
      final source = state.tasksByStatus[status] ?? const <Task>[];
      updated[status] = source.where((t) => t.id != task.id).toList();
    }

    if (_isTaskVisibleInBoard(task)) {
      updated[task.status] = [
        ...(updated[task.status] ?? const <Task>[]),
        task,
      ];
    }

    for (final status in TaskStatus.values) {
      updated[status] = (updated[status] ?? const <Task>[])
        ..sort((a, b) => a.position.compareTo(b.position));
    }

    state = state.copyWith(tasksByStatus: updated);
  }

  Future<void> createTask({
    required String title,
    String? description,
    String? assigneeId,
    TaskPriority priority = TaskPriority.medium,
    TaskIssueType issueType = TaskIssueType.task,
    String? epicId,
    String? sprintId,
    DateTime? dueDate,
    String? imageUrl,
  }) async {
    if (state.currentProjectId == null) return;

    try {
      await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'tasks',
        data: {
          'project_id': state.currentProjectId,
          'board_id': state.currentBoardId,
          'title': title,
          'description': description,
          'assignee_id': assigneeId,
          'creator_id': _supabaseService.currentUserId!,
          'priority': priority.name,
          'issue_type': issueType.name,
          'epic_id': epicId,
          'sprint_id': sprintId == '' ? null : (sprintId ?? state.activeSprintId),
          'due_date': dueDate?.toIso8601String(),
          'image_url': imageUrl,
          'position': _getNextPosition(TaskStatus.todo),
        },
        fromJson: (json) => json,
      );
      if (state.currentProjectId != null) {
        await loadTasks(state.currentProjectId!, boardId: state.currentBoardId);
      }
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
    TaskIssueType? issueType,
    String? epicId,
    String? sprintId,
    DateTime? dueDate,
    TaskStatus? status,
    String? imageUrl,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      if (title != null) updateData['title'] = title;
      if (description != null) updateData['description'] = description;
      if (assigneeId != null) updateData['assignee_id'] = assigneeId;
      if (priority != null) updateData['priority'] = priority.name;
      if (issueType != null) updateData['issue_type'] = issueType.name;
      if (epicId != null) updateData['epic_id'] = epicId;
      if (sprintId != null) updateData['sprint_id'] = sprintId.isEmpty ? null : sprintId;
      if (dueDate != null) updateData['due_date'] = dueDate.toIso8601String();
      if (status != null) updateData['status'] = status.toDbValue();
      if (imageUrl != null) updateData['image_url'] = imageUrl;

      await _supabaseService.update<Map<String, dynamic>>(
        tableName: 'tasks',
        id: taskId,
        data: updateData,
        fromJson: (json) => json,
      );
      if (state.currentProjectId != null) {
        await loadTasks(state.currentProjectId!, boardId: state.currentBoardId);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<String?> uploadTaskImage(String taskId, List<int> bytes, String extension) async {
    try {
      final fileName = '${taskId}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final path = 'attachments/$fileName';
      
      await _supabaseService.uploadFileBytes(
        bucket: 'task-attachments',
        path: path,
        bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      );
      
      return _supabaseService.getPublicUrl(bucket: 'task-attachments', path: path);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<void> deleteTask(String taskId) async {
    try {
      await _supabaseService.delete(tableName: 'tasks', id: taskId);
      if (state.currentProjectId != null) {
        await loadTasks(state.currentProjectId!, boardId: state.currentBoardId);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<List<Map<String, dynamic>>> getTaskComments(String taskId) async {
    try {
      return await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'task_comments',
        select: '*, users(full_name, email)',
        fromJson: (json) => json,
        filters: [QueryFilter('task_id', 'eq', taskId)],
        orderBy: [const Ordering('created_at', ascending: true)],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<void> addTaskComment({
    required String taskId,
    required String content,
  }) async {
    final userId = _supabaseService.currentUserId;
    if (userId == null) return;
    try {
      await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'task_comments',
        data: {
          'task_id': taskId,
          'user_id': userId,
          'content': content,
        },
        fromJson: (json) => json,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getTaskLinks(String taskId) async {
    try {
      return await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'task_links',
        fromJson: (json) => json,
        filters: [QueryFilter('task_id', 'eq', taskId)],
        orderBy: [const Ordering('created_at', ascending: true)],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<void> addTaskLink({
    required String taskId,
    required String url,
    String? title,
  }) async {
    try {
      await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'task_links',
        data: {
          'task_id': taskId,
          'url': url,
          'title': title,
          'created_by': _supabaseService.currentUserId,
        },
        fromJson: (json) => json,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> deleteTaskLink(String linkId) async {
    try {
      await _supabaseService.delete(tableName: 'task_links', id: linkId);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getTaskDocuments(String taskId) async {
    try {
      return await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'documents',
        fromJson: (json) => json,
        filters: [QueryFilter('task_id', 'eq', taskId)],
        orderBy: [const Ordering('updated_at', ascending: false)],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<Map<String, dynamic>?> createDocument({
    required String taskId,
    required String title,
    String content = '',
  }) async {
    try {
      final userId = _supabaseService.currentUserId;
      return await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'documents',
        data: {
          'task_id': taskId,
          'title': title,
          'content': content,
          'created_by': userId,
          'updated_by': userId,
        },
        fromJson: (json) => json,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateDocument({
    required String documentId,
    required String title,
    required String content,
  }) async {
    try {
      return await _supabaseService.update<Map<String, dynamic>>(
        tableName: 'documents',
        id: documentId,
        data: {
          'title': title,
          'content': content,
          'updated_by': _supabaseService.currentUserId,
        },
        fromJson: (json) => json,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
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

  void _activateDemoMode({required String message}) {
    state = state.copyWith(
      tasksByStatus: _generateDemoData(),
      isLoading: false,
      isDemoData: true,
      demoMessage: message,
      clearError: true,
    );
  }

  Map<TaskStatus, List<Task>> _generateDemoData() {
    const demoUser = TaskMember(
      id: 'demo-user',
      email: 'demo@taskflow.com',
      fullName: 'Demo User',
    );

    final now = DateTime.now();

    Task createTask({
      required String id,
      required String title,
      required TaskStatus status,
      TaskPriority priority = TaskPriority.medium,
      String? description,
      int position = 0,
      DateTime? dueDate,
    }) {
      return Task(
        id: id,
        projectId: 'demo-project',
        title: title,
        description: description,
        assigneeId: demoUser.id,
        creatorId: demoUser.id,
        status: status,
        priority: priority,
        dueDate: dueDate,
        position: position,
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(hours: 6)),
        assignee: demoUser,
        creator: demoUser,
      );
    }

    return {
      TaskStatus.todo: [
        createTask(
          id: 'demo-task-1',
          title: 'Настроить Supabase проект',
          description: 'Создайте проект, настройте таблицы и RLS политики.',
          status: TaskStatus.todo,
          priority: TaskPriority.high,
        ),
        createTask(
          id: 'demo-task-2',
          title: 'Прописать переменные окружения',
          description: 'Обновите SUPABASE_URL и SUPABASE_ANON_KEY в app_constants.dart.',
          status: TaskStatus.todo,
          priority: TaskPriority.medium,
          position: 1,
        ),
      ],
      TaskStatus.inProgress: [
        createTask(
          id: 'demo-task-3',
          title: 'Подготовить GitHub Actions',
          description: 'Настройте секреты и проверьте деплой.',
          status: TaskStatus.inProgress,
          priority: TaskPriority.high,
          position: 0,
        ),
      ],
      TaskStatus.review: [
        createTask(
          id: 'demo-task-4',
          title: 'Проверить drag & drop',
          description: 'Убедитесь, что перетаскивание работает на десктопе.',
          status: TaskStatus.review,
          priority: TaskPriority.medium,
          position: 0,
        ),
      ],
      TaskStatus.done: [
        createTask(
          id: 'demo-task-5',
          title: 'Запустить ./deploy.sh',
          description: 'Поднимите приложение на сервере через Docker.',
          status: TaskStatus.done,
          priority: TaskPriority.low,
          position: 0,
          dueDate: now.subtract(const Duration(days: 1)),
        ),
      ],
    };
  }

  @override
  void dispose() {
    _tasksChannel?.unsubscribe();
    _debounceTimer?.cancel();
    _realtimeReloadDebounceTimer?.cancel();
    super.dispose();
  }
}

// Providers
final kanbanProvider = StateNotifierProvider<KanbanNotifier, KanbanState>((ref) {
  final supabaseService = SupabaseClientService.instance;
  return KanbanNotifier(supabaseService);
});
