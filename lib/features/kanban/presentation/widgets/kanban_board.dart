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
    return Card(
      color: _getColumnColor(status).withAlpha(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getColumnColor(status).withAlpha(50),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getStatusIcon(status),
                  color: _getColumnColor(status),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _getStatusLabel(status),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _getColumnColor(status),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getColumnColor(status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${tasks.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  color: _getColumnColor(status),
                  onPressed: () => _showAddTaskDialog(context, ref, status),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
                      fromIndex: tasks.indexWhere((t) => t.id == task.id), // This logic is simplified
                      toIndex: tasks.length,
                    );
              },
              builder: (context, candidateData, rejectedData) {
                return Container(
                  decoration: BoxDecoration(
                    color: candidateData.isNotEmpty
                        ? _getColumnColor(status).withAlpha(30)
                        : Colors.transparent,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: tasks.isEmpty && candidateData.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No tasks',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
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
    final card = Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _showTaskDetails(context, ref, task),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.all(isDesktop ? 16 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Task Title
              Text(
                task.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              if (task.description != null && task.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  task.description!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                  maxLines: isDesktop ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // Bottom Row
              Row(
                children: [
                  _PriorityChip(priority: task.priority),
                  if (task.dueDate != null) ...[
                    const SizedBox(width: 8),
                    _DueDateChip(dueDate: task.dueDate!),
                  ],
                  const Spacer(),
                  if (task.assignee != null)
                    CircleAvatar(
                      radius: isDesktop ? 14 : 10,
                      backgroundColor: Theme.of(context).primaryColor.withAlpha(50),
                      child: Text(
                        (task.assignee!.fullName ?? task.assignee!.email)[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: isDesktop ? 10 : 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return LongPressDraggable<Task>(
      data: task,
      feedback: SizedBox(
        width: 300,
        child: Opacity(
          opacity: 0.8,
          child: card,
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
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
                              _PriorityChip(priority: task.priority),
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

// Priority Chip Widget
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(50),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(127)),
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

// Due Date Chip Widget
class _DueDateChip extends StatelessWidget {
  const _DueDateChip({required this.dueDate});

  final DateTime dueDate;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isOverdue = dueDate.isBefore(now);
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
      color = Colors.grey;
      text = '${dueDate.day}/${dueDate.month}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(50),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(127)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 12,
            color: color,
          ),
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
