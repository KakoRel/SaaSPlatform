import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saas_platform/features/kanban/domain/entities/task.dart';
import '../../providers/global_analytics_provider.dart';
import '../../providers/user_tasks_provider.dart';
import '../../../projects/providers/projects_provider.dart';

class GlobalAnalyticsScreen extends ConsumerWidget {
  const GlobalAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(userTasksStreamProvider);
    final projectsState = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Аналитика по всем проектам'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Ошибка: $e',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
        data: (allTasks) {
          final tasksByStatus = <TaskStatus, int>{
            for (final status in TaskStatus.values) status: 0,
          };
          for (final task in allTasks) {
            tasksByStatus[task.status] = (tasksByStatus[task.status] ?? 0) + 1;
          }

          final tasksByPriority = <TaskPriority, int>{
            for (final priority in TaskPriority.values) priority: 0,
          };
          for (final task in allTasks) {
            tasksByPriority[task.priority] = (tasksByPriority[task.priority] ?? 0) + 1;
          }

          final completedTasks = allTasks.where((t) => t.status == TaskStatus.done).length;
          final overdueTasks = allTasks
              .where((t) =>
                  t.dueDate != null &&
                  t.dueDate!.isBefore(DateTime.now()) &&
                  t.status != TaskStatus.done)
              .length;

          final totalTasks = allTasks.length;

          final projectsById = {
            for (final p in projectsState.projects) p.id: p.name,
          };

          final grouped = <String, List<Task>>{};
          for (final task in allTasks) {
            grouped.putIfAbsent(task.projectId, () => <Task>[]).add(task);
          }

          final tasksByProject = <String, ProjectTaskStats>{};
          for (final entry in grouped.entries) {
            final projectId = entry.key;
            final projectTasks = entry.value;

            final completedCount =
                projectTasks.where((t) => t.status == TaskStatus.done).length;
            final overdueCount = projectTasks.where((t) =>
                t.dueDate != null &&
                t.dueDate!.isBefore(DateTime.now()) &&
                t.status != TaskStatus.done).length;

            tasksByProject[projectId] = ProjectTaskStats(
              projectId: projectId,
              projectName: projectsById[projectId] ?? projectId,
              totalTasks: projectTasks.length,
              completedTasks: completedCount,
              overdueTasks: overdueCount,
            );
          }

          final analyticsState = GlobalAnalyticsState(
            totalProjects: projectsState.projects.isNotEmpty
                ? projectsState.projects.length
                : tasksByProject.keys.length,
            totalTasks: totalTasks,
            completedTasks: completedTasks,
            overdueTasks: overdueTasks,
            tasksByStatus: tasksByStatus,
            tasksByPriority: tasksByPriority,
            tasksByProject: tasksByProject,
            isLoading: false,
          );

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildGlobalSummary(analyticsState, context),
                    const SizedBox(height: 32),
                    _buildStatusBreakdown(analyticsState, context),
                    const SizedBox(height: 32),
                    _buildPriorityBreakdown(analyticsState, context),
                    const SizedBox(height: 32),
                    _buildProjectsBreakdown(analyticsState, context),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGlobalSummary(GlobalAnalyticsState state, BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Всего проектов',
                state.totalProjects.toString(),
                Icons.folder,
                Colors.blue,
                context,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Всего задач',
                state.totalTasks.toString(),
                Icons.task_alt,
                Colors.green,
                context,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Выполнено',
                state.completedTasks.toString(),
                Icons.check_circle,
                Colors.purple,
                context,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Просрочено',
                state.overdueTasks.toString(),
                Icons.warning,
                Colors.red,
                context,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color, BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBreakdown(GlobalAnalyticsState state, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Статус задач',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...TaskStatus.values.map((status) {
          final count = state.tasksByStatus[status] ?? 0;
          final percentage = state.totalTasks > 0 ? (count / state.totalTasks * 100).round() : 0;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getStatusName(status),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                Text(
                  '$count ($percentage%)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPriorityBreakdown(GlobalAnalyticsState state, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Приоритеты',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...TaskPriority.values.map((priority) {
          final count = state.tasksByPriority[priority] ?? 0;
          final percentage = state.totalTasks > 0 ? (count / state.totalTasks * 100).round() : 0;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getPriorityColor(priority),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getPriorityName(priority),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                Text(
                  '$count ($percentage%)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildProjectsBreakdown(GlobalAnalyticsState state, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Статистика по проектам',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...state.tasksByProject.entries.map((entry) {
          final projectStats = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          projectStats.projectName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${projectStats.completedTasks}/${projectStats.totalTasks}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: projectStats.completionRate,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      projectStats.completionRate >= 0.8 ? Colors.green :
                      projectStats.completionRate >= 0.5 ? Colors.orange : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(projectStats.completionRate * 100).round()}% выполнено',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (projectStats.overdueTasks > 0)
                        Text(
                          '${projectStats.overdueTasks} просрочено',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.todo:
        return Colors.grey;
      case TaskStatus.inProgress:
        return Colors.blue;
      case TaskStatus.review:
        return Colors.orange;
      case TaskStatus.done:
        return Colors.green;
    }
  }

  String _getStatusName(TaskStatus status) {
    switch (status) {
      case TaskStatus.todo:
        return 'К выполнению';
      case TaskStatus.inProgress:
        return 'В работе';
      case TaskStatus.review:
        return 'На проверке';
      case TaskStatus.done:
        return 'Выполнено';
    }
  }

  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return Colors.green;
      case TaskPriority.medium:
        return Colors.orange;
      case TaskPriority.high:
        return Colors.red;
      case TaskPriority.urgent:
        return Colors.purple;
    }
  }

  String _getPriorityName(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return 'Низкий';
      case TaskPriority.medium:
        return 'Средний';
      case TaskPriority.high:
        return 'Высокий';
      case TaskPriority.urgent:
        return 'Срочный';
    }
  }
}
