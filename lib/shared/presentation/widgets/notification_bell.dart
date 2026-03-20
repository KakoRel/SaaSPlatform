import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saas_platform/features/kanban/domain/entities/task.dart';
import 'package:saas_platform/features/analytics/providers/user_tasks_provider.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(userTasksProvider);
    final allTasks = tasksAsync.asData?.value ?? const [];
    
    final now = DateTime.now();
    final notifications = allTasks.where((task) {
      if (task.dueDate == null || task.status == TaskStatus.done) return false;
      // Overdue or due in the next 24 hours
      return task.dueDate!.isBefore(now) || 
             task.dueDate!.isBefore(now.add(const Duration(hours: 24)));
    }).toList();

    // Sort by most urgent first
    notifications.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    return Badge(
      isLabelVisible: notifications.isNotEmpty,
      label: Text(notifications.length.toString()),
      backgroundColor: Colors.redAccent,
      child: IconButton(
        icon: const Icon(Icons.notifications_outlined),
        onPressed: () => _showNotifications(context, notifications),
      ),
    );
  }

  void _showNotifications(BuildContext context, List<Task> notifications) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Дедлайны',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (notifications.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${notifications.length} задачи',
                      style: TextStyle(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('У вас нет срочных задач', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: notifications.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final task = notifications[index];
                    final isOverdue = task.dueDate!.isBefore(DateTime.now());
                    
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isOverdue ? Colors.red[50] : Colors.orange[50],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isOverdue ? Icons.warning_rounded : Icons.timer_outlined,
                          color: isOverdue ? Colors.red : Colors.orange,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        task.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Text(
                        isOverdue 
                          ? 'Просрочено: ${task.dueDate!.day}.${task.dueDate!.month}.${task.dueDate!.year}'
                          : 'Срок: ${task.dueDate!.day}.${task.dueDate!.month}.${task.dueDate!.year}',
                        style: TextStyle(
                          color: isOverdue ? Colors.red[700] : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
