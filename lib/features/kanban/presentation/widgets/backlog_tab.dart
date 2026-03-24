import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/task.dart';
import '../../providers/kanban_provider.dart';

class BacklogTab extends ConsumerStatefulWidget {
  const BacklogTab({
    super.key,
    required this.projectId,
    this.boardId,
  });

  final String projectId;
  final String? boardId;

  @override
  ConsumerState<BacklogTab> createState() => _BacklogTabState();
}

class _BacklogTabState extends ConsumerState<BacklogTab> {
  int _reloadKey = 0;

  void _refresh() {
    if (mounted) {
      setState(() => _reloadKey++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(kanbanProvider.notifier);

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_reloadKey),
      future: notifier.getProjectSprints(widget.projectId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final sprints = snapshot.data ?? [];
        Map<String, dynamic>? activeSprint;
        for (final sprint in sprints) {
          if (sprint['is_active'] == true) {
            activeSprint = sprint;
            break;
          }
        }
        final planningSprint =
            activeSprint ?? (sprints.isNotEmpty ? sprints.first : null);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _BacklogHeader(
                sprints: sprints,
                activeSprint: activeSprint,
                onCreateSprint: () async {
                  final created = await _showCreateSprintDialog(context, notifier);
                  if (created) _refresh();
                },
                onStartSprint: planningSprint == null
                    ? null
                    : () async {
                        final sprintId = planningSprint['id'] as String?;
                        if (sprintId == null) return;
                        final ok = await notifier.startSprint(
                          projectId: widget.projectId,
                          sprintId: sprintId,
                        );
                        if (ok) _refresh();
                      },
                onCompleteSprint: activeSprint == null
                    ? null
                    : () async {
                        final sprintId = activeSprint!['id'] as String?;
                        if (sprintId == null) return;
                        final ok = await notifier.completeSprint(
                          sprintId: sprintId,
                        );
                        if (ok) _refresh();
                      },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _TaskLane(
                        title: 'Бэклог',
                        subtitle: 'Без спринта',
                        loadTasks: () => notifier.getBacklogTasks(
                          projectId: widget.projectId,
                          boardId: widget.boardId,
                        ),
                        onDropTask: (taskId) async {
                          await notifier.moveTaskToSprint(taskId: taskId, sprintId: null);
                          _refresh();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: planningSprint == null
                          ? const _EmptySprintLane()
                          : _TaskLane(
                              title: 'Планирование спринта',
                              subtitle: planningSprint['name']?.toString() ?? 'Спринт',
                              loadTasks: () {
                                final sprintId = planningSprint['id'] as String?;
                                if (sprintId == null) return Future.value(<Task>[]);
                                return notifier.getSprintTasks(
                                  projectId: widget.projectId,
                                  sprintId: sprintId,
                                  boardId: widget.boardId,
                                );
                              },
                              onDropTask: (taskId) async {
                                final sprintId = planningSprint['id'] as String?;
                                if (sprintId == null) return;
                                await notifier.moveTaskToSprint(
                                  taskId: taskId,
                                  sprintId: sprintId,
                                );
                                _refresh();
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _showCreateSprintDialog(
    BuildContext context,
    KanbanNotifier notifier,
  ) async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый спринт'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название спринта',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (created == true && controller.text.trim().isNotEmpty) {
      final sprint = await notifier.createSprint(
        projectId: widget.projectId,
        name: controller.text.trim(),
      );
      return sprint != null;
    }
    return false;
  }
}

class _BacklogHeader extends StatelessWidget {
  const _BacklogHeader({
    required this.sprints,
    required this.activeSprint,
    required this.onCreateSprint,
    required this.onStartSprint,
    required this.onCompleteSprint,
  });

  final List<Map<String, dynamic>> sprints;
  final Map<String, dynamic>? activeSprint;
  final Future<void> Function() onCreateSprint;
  final Future<void> Function()? onStartSprint;
  final Future<void> Function()? onCompleteSprint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF252830),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              activeSprint == null
                  ? 'Активный спринт не запущен'
                  : 'Активный: ${activeSprint!['name']}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            'Спринтов: ${sprints.length}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onCreateSprint,
            icon: const Icon(Icons.add),
            label: const Text('Новый спринт'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onStartSprint,
            child: const Text('Начать спринт'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onCompleteSprint,
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
  }
}

class _TaskLane extends StatelessWidget {
  const _TaskLane({
    required this.title,
    required this.subtitle,
    required this.loadTasks,
    required this.onDropTask,
  });

  final String title;
  final String subtitle;
  final Future<List<Task>> Function() loadTasks;
  final Future<void> Function(String taskId) onDropTask;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252830),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF323844)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: DragTarget<String>(
              onAcceptWithDetails: (details) => onDropTask(details.data),
              builder: (context, candidateData, rejectedData) {
                return FutureBuilder<List<Task>>(
                  future: loadTasks(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    final tasks = snapshot.data ?? [];
                    if (tasks.isEmpty) {
                      return const Center(
                        child: Text('Нет задач', style: TextStyle(color: Colors.white54)),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _BacklogTaskTile(task: tasks[index]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BacklogTaskTile extends StatelessWidget {
  const _BacklogTaskTile({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: task.id,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 360,
          child: _buildCard(),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _buildCard()),
      child: _buildCard(),
    );
  }

  Widget _buildCard() {
    final typeLabel = switch (task.issueType) {
      TaskIssueType.epic => 'ЭПИК',
      TaskIssueType.story => 'ИСТОРИЯ',
      TaskIssueType.task => 'ЗАДАЧА',
      TaskIssueType.bug => 'БАГ',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              typeLabel,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySprintLane extends StatelessWidget {
  const _EmptySprintLane();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252830),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF323844)),
      ),
      child: const Center(
        child: Text(
          'Создайте спринт для планирования задач',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
