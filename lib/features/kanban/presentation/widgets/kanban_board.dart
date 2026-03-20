import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/task.dart';
import '../../providers/kanban_provider.dart';
import '../../../../shared/presentation/widgets/adaptive_layout.dart';
import 'task_form_dialog.dart';

class KanbanBoardWidget extends ConsumerStatefulWidget {
  const KanbanBoardWidget({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<KanbanBoardWidget> createState() => _KanbanBoardWidgetState();
}

class _KanbanBoardWidgetState extends ConsumerState<KanbanBoardWidget> {
  @override
  void initState() {
    super.initState();
    // Load tasks on init
    Future.microtask(() {
      ref.read(kanbanProvider.notifier).loadTasks(widget.projectId);
    });
  }

  @override
  void didUpdateWidget(covariant KanbanBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      ref.read(kanbanProvider.notifier).loadTasks(widget.projectId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kanbanState = ref.watch(kanbanProvider);
    final kanbanNotifier = ref.read(kanbanProvider.notifier);

    if (kanbanState.isLoading && kanbanState.tasksByStatus.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (kanbanState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading tasks',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              kanbanState.error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => kanbanNotifier.loadTasks(widget.projectId),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return AdaptiveLayout(
      mobile: _MobileKanbanBoard(
        tasksByStatus: kanbanState.tasksByStatus,
      ),
      tablet: _TabletKanbanBoard(
        tasksByStatus: kanbanState.tasksByStatus,
      ),
      desktop: _DesktopKanbanBoard(
        tasksByStatus: kanbanState.tasksByStatus,
      ),
    );
  }
}

// Mobile Layout - Vertical scrolling
class _MobileKanbanBoard extends StatelessWidget {
  const _MobileKanbanBoard({
    required this.tasksByStatus,
  });

  final Map<TaskStatus, List<Task>> tasksByStatus;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: TaskStatus.values.map((status) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _KanbanColumn(
              status: status,
              tasks: tasksByStatus[status] ?? [],
              isMobile: true,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Tablet Layout - Horizontal scrolling
class _TabletKanbanBoard extends StatelessWidget {
  const _TabletKanbanBoard({
    required this.tasksByStatus,
  });

  final Map<TaskStatus, List<Task>> tasksByStatus;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: TaskStatus.values.map((status) {
          return SizedBox(
            width: 350,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _KanbanColumn(
                status: status,
                tasks: tasksByStatus[status] ?? [],
                isMobile: false,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Desktop Layout - Expanded Kanban Board
class _DesktopKanbanBoard extends StatelessWidget {
  const _DesktopKanbanBoard({
    required this.tasksByStatus,
  });

  final Map<TaskStatus, List<Task>> tasksByStatus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: TaskStatus.values.map((status) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _KanbanColumn(
                status: status,
                tasks: tasksByStatus[status] ?? [],
                isMobile: false,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Individual Kanban Column
class _KanbanColumn extends ConsumerWidget {
  const _KanbanColumn({
    required this.status,
    required this.tasks,
    required this.isMobile,
  });

  final TaskStatus status;
  final List<Task> tasks;
  final bool isMobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _getColumnColor(status);
    
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_getStatusIcon(status), color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _getStatusLabel(status),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: color.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    '${tasks.length}',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 22),
                  color: color,
                  onPressed: () => _showAddTaskDialog(context, ref, status),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          
          // Tasks List
          Expanded(
            child: DragTarget<Task>(
              onWillAcceptWithDetails: (details) => details.data.status != status,
              onAcceptWithDetails: (details) {
                final task = details.data;
                ref.read(kanbanProvider.notifier).handleDragDrop(
                      taskId: task.id,
                      fromStatus: task.status,
                      toStatus: status,
                      fromIndex: tasks.indexWhere((t) => t.id == task.id),
                      toIndex: tasks.length,
                    );
              },
              builder: (context, candidateData, rejectedData) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  color: candidateData.isNotEmpty
                      ? color.withValues(alpha: 0.1)
                      : Colors.transparent,
                  child: tasks.isEmpty && candidateData.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.layers_outlined, size: 48, color: color.withValues(alpha: 0.2)),
                              const SizedBox(height: 12),
                              Text(
                                'Empty Column',
                                style: TextStyle(color: color.withValues(alpha: 0.3), fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _TaskCard(task: tasks[index], isDesktop: !isMobile);
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context, WidgetRef ref, TaskStatus status) {
    showDialog(
      context: context,
      builder: (context) => TaskFormDialog(initialStatus: status),
    );
  }
}

// Task Card Widget
class _TaskCard extends ConsumerWidget {
  const _TaskCard({
    required this.task,
    required this.isDesktop,
  });

  final Task task;
  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Priority Bar
              Container(
                width: 5,
                color: _getPriorityColor(task.priority),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _showTaskDetails(context, ref, task),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (task.assignee != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.blue[50],
                                  child: Text(
                                    (task.assignee!.fullName ?? task.assignee!.email)[0].toUpperCase(),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (task.description != null && task.description!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            task.description!,
                            style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _PriorityBadge(priority: task.priority),
                            if (task.dueDate != null) ...[
                              const SizedBox(width: 8),
                              _DueDateBadge(dueDate: task.dueDate!),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return LongPressDraggable<Task>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 280,
          child: Opacity(
            opacity: 0.9,
            child: card,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: card,
      ),
      child: card,
    );
  }

  void _showTaskDetails(BuildContext context, WidgetRef ref, Task task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailsSheet(task: task),
    );
  }

  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low: return Colors.green;
      case TaskPriority.medium: return Colors.blue;
      case TaskPriority.high: return Colors.orange;
      case TaskPriority.urgent: return Colors.red;
    }
  }
}

// Task Details Sheet
class TaskDetailsSheet extends ConsumerWidget {
  const TaskDetailsSheet({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Actions Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          builder: (context) => TaskFormDialog(task: task),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmDelete(context, ref),
                    ),
                  ],
                ),
              ),

              // Task Details
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),

                    if (task.description != null && task.description!.isNotEmpty) ...[
                      Text(
                        'Description',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(task.description!),
                      const SizedBox(height: 24),
                    ],

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Priority',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              _PriorityBadge(priority: task.priority),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Status',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getColumnColor(task.status).withAlpha(50),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _getStatusLabel(task.status),
                                  style: TextStyle(
                                    color: _getColumnColor(task.status),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (task.dueDate != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Deadline',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text('${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}'),
                        ],
                      ),
                    ],

                    if (task.assignee != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Assignee',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Theme.of(context).primaryColor.withAlpha(50),
                            child: Text(
                              (task.assignee!.fullName ?? task.assignee!.email)[0].toUpperCase(),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(task.assignee!.fullName ?? 'No Name'),
                              Text(
                                task.assignee!.email,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure you want to delete this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(kanbanProvider.notifier).deleteTask(task.id);
              Navigator.pop(context); // Close confirm dialog
              Navigator.pop(context); // Close bottom sheet
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// Priority Badge Widget
class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        priority.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// Due Date Badge Widget
class _DueDateBadge extends StatelessWidget {
  const _DueDateBadge({required this.dueDate});

  final DateTime dueDate;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isOverdue = dueDate.isBefore(DateTime(now.year, now.month, now.day));
    final isToday = dueDate.day == now.day && dueDate.month == now.month && dueDate.year == now.year;
    
    Color color;
    String text;
    
    if (isOverdue) {
      color = Colors.red;
      text = 'Overdue';
    } else if (isToday) {
      color = Colors.orange;
      text = 'Today';
    } else {
      color = Colors.blueGrey;
      text = '${dueDate.day}/${dueDate.month}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_rounded, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// Helper functions
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

Color _getColumnColor(TaskStatus status) {
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

IconData _getStatusIcon(TaskStatus status) {
  switch (status) {
    case TaskStatus.todo:
      return Icons.inbox_outlined;
    case TaskStatus.inProgress:
      return Icons.pending_outlined;
    case TaskStatus.review:
      return Icons.rate_review_outlined;
    case TaskStatus.done:
      return Icons.check_circle_outline;
  }
}
