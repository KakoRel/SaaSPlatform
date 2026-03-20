import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saas_platform/features/kanban/domain/entities/task.dart';
import 'package:saas_platform/features/kanban/providers/kanban_provider.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kanbanState = ref.watch(kanbanProvider);
    final allTasks = kanbanState.tasksByStatus.values.expand((tasks) => tasks).toList();
    
    final totalTasks = allTasks.length;
    final overdueTasks = allTasks.where((t) => t.dueDate != null && t.dueDate!.isBefore(DateTime.now()) && t.status != TaskStatus.done).length;
    final completedTasks = allTasks.where((t) => t.status == TaskStatus.done).length;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Аналитика'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildSummaryCards(totalTasks, overdueTasks, completedTasks),
                const SizedBox(height: 32),
                Text(
                  'Статус задач',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildStatusBreakdown(kanbanState.tasksByStatus, totalTasks),
                const SizedBox(height: 32),
                Text(
                  'Приоритеты',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildPriorityBreakdown(allTasks, totalTasks),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(int total, int overdue, int completed) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Всего', total.toString(), Colors.blue)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Просрочено', overdue.toString(), Colors.red)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Готово', completed.toString(), Colors.green)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatusBreakdown(Map<TaskStatus, List<Task>> tasksByStatus, int total) {
    return Column(
      children: TaskStatus.values.map((status) {
        final count = tasksByStatus[status]?.length ?? 0;
        final percent = total > 0 ? count / total : 0.0;
        final color = _getStatusColor(status);
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_getStatusLabel(status), style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text('$count (${(percent * 100).toStringAsFixed(0)}%)'),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent,
                  backgroundColor: color.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPriorityBreakdown(List<Task> allTasks, int total) {
    return Column(
      children: TaskPriority.values.map((priority) {
        final count = allTasks.where((t) => t.priority == priority).length;
        final percent = total > 0 ? count / total : 0.0;
        final color = _getPriorityColor(priority);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_getPriorityLabel(priority), style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text('$count (${(percent * 100).toStringAsFixed(0)}%)'),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent,
                  backgroundColor: color.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.todo: return Colors.grey;
      case TaskStatus.inProgress: return Colors.blue;
      case TaskStatus.review: return Colors.orange;
      case TaskStatus.done: return Colors.green;
    }
  }

  String _getStatusLabel(TaskStatus status) {
    switch (status) {
      case TaskStatus.todo: return 'To Do';
      case TaskStatus.inProgress: return 'In Progress';
      case TaskStatus.review: return 'Review';
      case TaskStatus.done: return 'Done';
    }
  }

  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low: return Colors.blue;
      case TaskPriority.medium: return Colors.orange;
      case TaskPriority.high: return Colors.red;
      case TaskPriority.urgent: return Colors.deepPurple;
    }
  }

  String _getPriorityLabel(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low: return 'Низкий';
      case TaskPriority.medium: return 'Средний';
      case TaskPriority.high: return 'Высокий';
      case TaskPriority.urgent: return 'Критический';
    }
  }
}
