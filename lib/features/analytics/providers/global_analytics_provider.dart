import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../kanban/domain/entities/task.dart';
import '../../kanban/providers/kanban_provider.dart';
import '../../projects/providers/projects_provider.dart';

class GlobalAnalyticsState {
  const GlobalAnalyticsState({
    this.totalProjects = 0,
    this.totalTasks = 0,
    this.completedTasks = 0,
    this.overdueTasks = 0,
    this.tasksByStatus = const {},
    this.tasksByPriority = const {},
    this.tasksByProject = const {},
    this.isLoading = false,
    this.error,
  });

  final int totalProjects;
  final int totalTasks;
  final int completedTasks;
  final int overdueTasks;
  final Map<TaskStatus, int> tasksByStatus;
  final Map<TaskPriority, int> tasksByPriority;
  final Map<String, ProjectTaskStats> tasksByProject;
  final bool isLoading;
  final String? error;

  GlobalAnalyticsState copyWith({
    int? totalProjects,
    int? totalTasks,
    int? completedTasks,
    int? overdueTasks,
    Map<TaskStatus, int>? tasksByStatus,
    Map<TaskPriority, int>? tasksByPriority,
    Map<String, ProjectTaskStats>? tasksByProject,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return GlobalAnalyticsState(
      totalProjects: totalProjects ?? this.totalProjects,
      totalTasks: totalTasks ?? this.totalTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      overdueTasks: overdueTasks ?? this.overdueTasks,
      tasksByStatus: tasksByStatus ?? this.tasksByStatus,
      tasksByPriority: tasksByPriority ?? this.tasksByPriority,
      tasksByProject: tasksByProject ?? this.tasksByProject,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ProjectTaskStats {
  const ProjectTaskStats({
    required this.projectId,
    required this.projectName,
    this.totalTasks = 0,
    this.completedTasks = 0,
    this.overdueTasks = 0,
  });

  final String projectId;
  final String projectName;
  final int totalTasks;
  final int completedTasks;
  final int overdueTasks;

  double get completionRate => totalTasks > 0 ? completedTasks / totalTasks : 0.0;
}

class GlobalAnalyticsNotifier extends StateNotifier<GlobalAnalyticsState> {
  GlobalAnalyticsNotifier(this.ref) : super(const GlobalAnalyticsState()) {
    _loadAnalytics();
  }

  final Ref ref;

  Future<void> _loadAnalytics() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final projectsState = ref.read(projectsProvider);
      final kanbanState = ref.read(kanbanProvider);

      // Get all projects
      final projects = projectsState.projects;
      
      // Collect all tasks from all projects
      final allTasks = <Task>[];
      final tasksByProject = <String, ProjectTaskStats>{};

      for (final project in projects) {
        // Get tasks for this project (you'll need to modify KanbanProvider to support this)
        final projectTasks = kanbanState.tasksByStatus.values
            .expand((tasks) => tasks)
            .where((task) => task.projectId == project.id)
            .toList();

        allTasks.addAll(projectTasks);

        final completedCount = projectTasks.where((t) => t.status == TaskStatus.done).length;
        final overdueCount = projectTasks.where((t) => 
            t.dueDate != null && 
            t.dueDate!.isBefore(DateTime.now()) && 
            t.status != TaskStatus.done
        ).length;

        tasksByProject[project.id] = ProjectTaskStats(
          projectId: project.id,
          projectName: project.name,
          totalTasks: projectTasks.length,
          completedTasks: completedCount,
          overdueTasks: overdueCount,
        );
      }

      // Calculate global stats
      final totalTasks = allTasks.length;
      final completedTasks = allTasks.where((t) => t.status == TaskStatus.done).length;
      final overdueTasks = allTasks.where((t) => 
          t.dueDate != null && 
          t.dueDate!.isBefore(DateTime.now()) && 
          t.status != TaskStatus.done
      ).length;

      // Tasks by status
      final tasksByStatus = <TaskStatus, int>{};
      for (final status in TaskStatus.values) {
        tasksByStatus[status] = allTasks.where((t) => t.status == status).length;
      }

      // Tasks by priority
      final tasksByPriority = <TaskPriority, int>{};
      for (final priority in TaskPriority.values) {
        tasksByPriority[priority] = allTasks.where((t) => t.priority == priority).length;
      }

      state = state.copyWith(
        totalProjects: projects.length,
        totalTasks: totalTasks,
        completedTasks: completedTasks,
        overdueTasks: overdueTasks,
        tasksByStatus: tasksByStatus,
        tasksByPriority: tasksByPriority,
        tasksByProject: tasksByProject,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    await _loadAnalytics();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// Providers
final globalAnalyticsProvider = StateNotifierProvider<GlobalAnalyticsNotifier, GlobalAnalyticsState>((ref) {
  return GlobalAnalyticsNotifier(ref);
});
