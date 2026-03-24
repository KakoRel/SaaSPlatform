import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/task.dart';
import '../../providers/kanban_provider.dart';
import '../../../../shared/presentation/widgets/adaptive_layout.dart';
import '../../../../core/services/supabase_client.dart';
import 'task_form_dialog.dart';
import 'document_editor_screen.dart';

class KanbanBoardWidget extends ConsumerStatefulWidget {
  const KanbanBoardWidget({
    super.key,
    required this.projectId,
    this.boardId,
    this.searchQuery = '',
    this.onNavigateToBacklog,
  });

  final String projectId;
  final String? boardId;
  final String searchQuery;
  final VoidCallback? onNavigateToBacklog;

  @override
  ConsumerState<KanbanBoardWidget> createState() => _KanbanBoardWidgetState();
}

class _KanbanBoardWidgetState extends ConsumerState<KanbanBoardWidget> {
  String _searchQuery = '';
  String _selectedAssigneeId = '';
  String _selectedIssueType = '';
  BoardGrouping _grouping = BoardGrouping.none;
  String _selectedCreatorId = '';
  String _selectedPriority = '';
  DueDateFilter _dueDateFilter = DueDateFilter.all;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchQuery = widget.searchQuery;
    _searchController.text = widget.searchQuery;
    // Load tasks on init
    Future.microtask(() {
      ref.read(kanbanProvider.notifier).loadTasks(
            widget.projectId,
            boardId: widget.boardId,
          );
    });
  }

  @override
  void didUpdateWidget(covariant KanbanBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _searchQuery = widget.searchQuery;
      if (_searchController.text != widget.searchQuery) {
        _searchController.text = widget.searchQuery;
      }
    }
    if (oldWidget.projectId != widget.projectId || oldWidget.boardId != widget.boardId) {
      ref.read(kanbanProvider.notifier).loadTasks(
            widget.projectId,
            boardId: widget.boardId,
          );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              'Ошибка загрузки задач',
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
              onPressed: () => kanbanNotifier.loadTasks(
                widget.projectId,
                boardId: widget.boardId,
              ),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final allTasks = kanbanState.tasksByStatus.values.expand((tasks) => tasks).toList();
    final assignees = <TaskMember>[];
    final creators = <TaskMember>[];
    final seenAssigneeIds = <String>{};
    final seenCreatorIds = <String>{};
    for (final task in allTasks) {
      final assignee = task.assignee;
      if (assignee == null || seenAssigneeIds.contains(assignee.id)) continue;
      seenAssigneeIds.add(assignee.id);
      assignees.add(assignee);
    }
    for (final task in allTasks) {
      final creator = task.creator;
      if (creator == null || seenCreatorIds.contains(creator.id)) continue;
      seenCreatorIds.add(creator.id);
      creators.add(creator);
    }

    final filteredByStatus = <TaskStatus, List<Task>>{
      for (final status in TaskStatus.values)
        status: (kanbanState.tasksByStatus[status] ?? []).where((task) {
          final today = DateTime.now();
          final todayDate = DateTime(today.year, today.month, today.day);
          final dueDateOnly = task.dueDate == null
              ? null
              : DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day);
          final matchesQuery = _searchQuery.trim().isEmpty ||
              task.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (task.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
          final matchesAssignee =
              _selectedAssigneeId.isEmpty || task.assigneeId == _selectedAssigneeId;
          final matchesType =
              _selectedIssueType.isEmpty || task.issueType.name == _selectedIssueType;
          final matchesCreator =
              _selectedCreatorId.isEmpty || task.creatorId == _selectedCreatorId;
          final matchesPriority =
              _selectedPriority.isEmpty || task.priority.name == _selectedPriority;
          final matchesDueDate = switch (_dueDateFilter) {
            DueDateFilter.all => true,
            DueDateFilter.overdue => dueDateOnly != null && dueDateOnly.isBefore(todayDate),
            DueDateFilter.today => dueDateOnly != null && dueDateOnly == todayDate,
            DueDateFilter.upcoming => dueDateOnly != null && dueDateOnly.isAfter(todayDate),
            DueDateFilter.noDueDate => task.dueDate == null,
          };
          return matchesQuery &&
              matchesAssignee &&
              matchesType &&
              matchesCreator &&
              matchesPriority &&
              matchesDueDate;
        }).toList(),
    };
    final epicTitlesById = <String, String>{
      for (final task in allTasks)
        if (task.issueType == TaskIssueType.epic) task.id: task.title,
    };

    return Column(
      children: [
        _BoardFiltersBar(
          searchController: _searchController,
          selectedAssigneeId: _selectedAssigneeId,
          selectedIssueType: _selectedIssueType,
          selectedCreatorId: _selectedCreatorId,
          selectedPriority: _selectedPriority,
          dueDateFilter: _dueDateFilter,
          grouping: _grouping,
          assignees: assignees,
          creators: creators,
          onSearchChanged: (value) => setState(() => _searchQuery = value),
          onAssigneeChanged: (value) => setState(() => _selectedAssigneeId = value ?? ''),
          onIssueTypeChanged: (value) => setState(() => _selectedIssueType = value ?? ''),
          onCreatorChanged: (value) => setState(() => _selectedCreatorId = value ?? ''),
          onPriorityChanged: (value) => setState(() => _selectedPriority = value ?? ''),
          onDueDateFilterChanged: (value) => setState(() => _dueDateFilter = value ?? DueDateFilter.all),
          onGroupingChanged: (value) => setState(() => _grouping = value ?? BoardGrouping.none),
          onReset: () {
            setState(() {
              _searchQuery = '';
              _searchController.clear();
              _selectedAssigneeId = '';
              _selectedIssueType = '';
              _selectedCreatorId = '';
              _selectedPriority = '';
              _dueDateFilter = DueDateFilter.all;
              _grouping = BoardGrouping.none;
            });
          },
        ),
        Expanded(
          child: _grouping == BoardGrouping.none
              ? AdaptiveLayout(
                  mobile: _MobileKanbanBoard(
                    tasksByStatus: filteredByStatus,
                    onNavigateToBacklog: widget.onNavigateToBacklog,
                  ),
                  tablet: _TabletKanbanBoard(
                    tasksByStatus: filteredByStatus,
                    onNavigateToBacklog: widget.onNavigateToBacklog,
                  ),
                  desktop: _DesktopKanbanBoard(
                    tasksByStatus: filteredByStatus,
                    onNavigateToBacklog: widget.onNavigateToBacklog,
                  ),
                )
              : _GroupedKanbanBoard(
                  allTasks: filteredByStatus.values.expand((tasks) => tasks).toList(),
                  grouping: _grouping,
                  epicTitlesById: epicTitlesById,
                  onNavigateToBacklog: widget.onNavigateToBacklog,
                ),
        ),
      ],
    );
  }
}

enum BoardGrouping { none, assignee, epic }
enum DueDateFilter { all, overdue, today, upcoming, noDueDate }

class _BoardFiltersBar extends StatelessWidget {
  const _BoardFiltersBar({
    required this.searchController,
    required this.selectedAssigneeId,
    required this.selectedIssueType,
    required this.selectedCreatorId,
    required this.selectedPriority,
    required this.dueDateFilter,
    required this.grouping,
    required this.assignees,
    required this.creators,
    required this.onSearchChanged,
    required this.onAssigneeChanged,
    required this.onIssueTypeChanged,
    required this.onCreatorChanged,
    required this.onPriorityChanged,
    required this.onDueDateFilterChanged,
    required this.onGroupingChanged,
    required this.onReset,
  });

  final TextEditingController searchController;
  final String selectedAssigneeId;
  final String selectedIssueType;
  final String selectedCreatorId;
  final String selectedPriority;
  final DueDateFilter dueDateFilter;
  final BoardGrouping grouping;
  final List<TaskMember> assignees;
  final List<TaskMember> creators;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onAssigneeChanged;
  final ValueChanged<String?> onIssueTypeChanged;
  final ValueChanged<String?> onCreatorChanged;
  final ValueChanged<String?> onPriorityChanged;
  final ValueChanged<DueDateFilter?> onDueDateFilterChanged;
  final ValueChanged<BoardGrouping?> onGroupingChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
          SizedBox(
            width: 320,
            child: TextFormField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Поиск по задачам',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: selectedAssigneeId.isEmpty ? null : selectedAssigneeId,
            hint: const Text('Исполнитель'),
            items: [
              const DropdownMenuItem<String>(value: '', child: Text('Все')),
              ...assignees.map(
                (member) => DropdownMenuItem<String>(
                  value: member.id,
                  child: Text(member.fullName ?? member.email),
                ),
              ),
            ],
            onChanged: onAssigneeChanged,
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: selectedIssueType.isEmpty ? null : selectedIssueType,
            hint: const Text('Тип'),
            items: const [
              DropdownMenuItem<String>(value: '', child: Text('Все')),
              DropdownMenuItem<String>(value: 'epic', child: Text('Эпик')),
              DropdownMenuItem<String>(value: 'story', child: Text('История')),
              DropdownMenuItem<String>(value: 'task', child: Text('Задача')),
              DropdownMenuItem<String>(value: 'bug', child: Text('Баг')),
            ],
            onChanged: onIssueTypeChanged,
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: selectedCreatorId.isEmpty ? null : selectedCreatorId,
            hint: const Text('Создатель'),
            items: [
              const DropdownMenuItem<String>(value: '', child: Text('Все')),
              ...creators.map(
                (member) => DropdownMenuItem<String>(
                  value: member.id,
                  child: Text(member.fullName ?? member.email),
                ),
              ),
            ],
            onChanged: onCreatorChanged,
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: selectedPriority.isEmpty ? null : selectedPriority,
            hint: const Text('Приоритет'),
            items: const [
              DropdownMenuItem<String>(value: '', child: Text('Все')),
              DropdownMenuItem<String>(value: 'low', child: Text('Низкий')),
              DropdownMenuItem<String>(value: 'medium', child: Text('Средний')),
              DropdownMenuItem<String>(value: 'high', child: Text('Высокий')),
              DropdownMenuItem<String>(value: 'urgent', child: Text('Срочный')),
            ],
            onChanged: onPriorityChanged,
          ),
          const SizedBox(width: 8),
          DropdownButton<DueDateFilter>(
            value: dueDateFilter,
            items: const [
              DropdownMenuItem(value: DueDateFilter.all, child: Text('Все сроки')),
              DropdownMenuItem(value: DueDateFilter.overdue, child: Text('Просроченные')),
              DropdownMenuItem(value: DueDateFilter.today, child: Text('На сегодня')),
              DropdownMenuItem(value: DueDateFilter.upcoming, child: Text('Предстоящие')),
              DropdownMenuItem(value: DueDateFilter.noDueDate, child: Text('Без срока')),
            ],
            onChanged: onDueDateFilterChanged,
          ),
          const SizedBox(width: 8),
          DropdownButton<BoardGrouping>(
            value: grouping,
            items: const [
              DropdownMenuItem(
                value: BoardGrouping.none,
                child: Text('Без группировки'),
              ),
              DropdownMenuItem(
                value: BoardGrouping.assignee,
                child: Text('По исполнителю'),
              ),
              DropdownMenuItem(
                value: BoardGrouping.epic,
                child: Text('По эпику'),
              ),
            ],
            onChanged: onGroupingChanged,
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.clear_all),
            label: const Text('Сбросить'),
          ),
          ],
        ),
      ),
    );
  }
}

class _GroupedKanbanBoard extends StatelessWidget {
  const _GroupedKanbanBoard({
    required this.allTasks,
    required this.grouping,
    required this.epicTitlesById,
    this.onNavigateToBacklog,
  });

  final List<Task> allTasks;
  final BoardGrouping grouping;
  final Map<String, String> epicTitlesById;
  final VoidCallback? onNavigateToBacklog;

  @override
  Widget build(BuildContext context) {
    final lanes = <String, List<Task>>{};
    for (final task in allTasks) {
      final key = switch (grouping) {
        BoardGrouping.assignee =>
          task.assignee?.fullName ?? task.assignee?.email ?? 'Не назначен',
        BoardGrouping.epic => task.epicId == null
            ? 'Без эпика'
            : (epicTitlesById[task.epicId!] ?? 'Эпик ${task.epicId!.substring(0, 8)}'),
        BoardGrouping.none => 'Все задачи',
      };
      lanes.putIfAbsent(key, () => []);
      lanes[key]!.add(task);
    }
    if (lanes.isEmpty) {
      lanes['Нет задач'] = [];
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: lanes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final laneTitle = lanes.keys.elementAt(index);
        final laneTasks = lanes.values.elementAt(index);
        final tasksByStatus = <TaskStatus, List<Task>>{
          for (final status in TaskStatus.values) status: [],
        };
        for (final task in laneTasks) {
          tasksByStatus[task.status]!.add(task);
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF23262D),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF303541)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  laneTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 520,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: TaskStatus.values.map((status) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _KanbanColumn(
                            status: status,
                            tasks: tasksByStatus[status] ?? const [],
                            isMobile: false,
                            onNavigateToBacklog: onNavigateToBacklog,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Mobile Layout - Vertical scrolling
class _MobileKanbanBoard extends StatelessWidget {
  const _MobileKanbanBoard({
    required this.tasksByStatus,
    this.onNavigateToBacklog,
  });

  final Map<TaskStatus, List<Task>> tasksByStatus;
  final VoidCallback? onNavigateToBacklog;

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
              onNavigateToBacklog: onNavigateToBacklog,
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
    this.onNavigateToBacklog,
  });

  final Map<TaskStatus, List<Task>> tasksByStatus;
  final VoidCallback? onNavigateToBacklog;

  @override
  Widget build(BuildContext context) {
    // На web при фиксированной ширине колонок интерфейс "раздувается".
    // Масштабируем ширину колонок от текущего viewport'а.
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final rawColumnWidth = viewportWidth / TaskStatus.values.length;
        final columnWidth = rawColumnWidth.clamp(240.0, 350.0);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: viewportWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: TaskStatus.values.map((status) {
                return SizedBox(
                  width: columnWidth,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _KanbanColumn(
                      status: status,
                      tasks: tasksByStatus[status] ?? [],
                      isMobile: false,
                      onNavigateToBacklog: onNavigateToBacklog,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

// Desktop Layout - Expanded Kanban Board
class _DesktopKanbanBoard extends StatelessWidget {
  const _DesktopKanbanBoard({
    required this.tasksByStatus,
    this.onNavigateToBacklog,
  });

  final Map<TaskStatus, List<Task>> tasksByStatus;
  final VoidCallback? onNavigateToBacklog;

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
                onNavigateToBacklog: onNavigateToBacklog,
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
    this.onNavigateToBacklog,
  });

  final TaskStatus status;
  final List<Task> tasks;
  final bool isMobile;
  final VoidCallback? onNavigateToBacklog;

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
          isMobile 
            ? _buildTaskList(context, ref, color)
            : Expanded(child: _buildTaskList(context, ref, color)),
        ],
      ),
    );
  }

  Widget _buildTaskList(BuildContext context, WidgetRef ref, Color color) {
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) => (details.data['task'] as Task).status != status,
      onAcceptWithDetails: (details) {
        final task = details.data['task'] as Task;
        final fromIndex = details.data['index'] as int;
        ref.read(kanbanProvider.notifier).handleDragDrop(
              taskId: task.id,
              fromStatus: task.status,
              toStatus: status,
              fromIndex: fromIndex,
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
              ? _buildEmptyState(color)
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  shrinkWrap: isMobile,
                  physics: isMobile ? const NeverScrollableScrollPhysics() : null,
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    return _TaskCard(task: tasks[index], isDesktop: !isMobile, index: index);
                  },
                ),
        );
      },
    );
  }

  Widget _buildEmptyState(Color color) {
    if (status == TaskStatus.todo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.autorenew_rounded, size: 44, color: Colors.white30),
              const SizedBox(height: 10),
              const Text(
                'Начните работу в бэклоге',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Запланируйте и начните спринт,\nчтобы увидеть здесь задачи.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onNavigateToBacklog,
                child: const Text('Перейти в бэклог'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.layers_outlined, size: 48, color: color.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            Text(
              'Пустая колонка',
              style: TextStyle(color: color.withValues(alpha: 0.3), fontSize: 13),
            ),
          ],
        ),
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
    required this.index,
  });

  final Task task;
  final bool isDesktop;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = SupabaseClientService.instance.currentUserId;
    final isAssignedToMe = currentUserId != null && task.assigneeId == currentUserId;

    final card = Container(
      decoration: BoxDecoration(
        color: isAssignedToMe ? Colors.blue.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isAssignedToMe
              ? Colors.blueAccent.withValues(alpha: 0.35)
              : Colors.grey.withValues(alpha: 0.1),
          width: isAssignedToMe ? 1.5 : 1,
        ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task.imageUrl != null)
                        Image.network(
                          task.imageUrl!,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                        ),
                      Padding(
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
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withAlpha(30),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.withAlpha(60)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.person_off_outlined, size: 14, color: Colors.grey),
                                      SizedBox(width: 6),
                                      Text(
                                        'Не назначен',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
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
                            _IssueTypeBadge(issueType: task.issueType),
                            const SizedBox(width: 8),
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Draggable<Map<String, dynamic>>(
      data: {'task': task, 'index': index},
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: isDesktop ? 280 : MediaQuery.of(context).size.width * 0.8,
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
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 1100,
          height: MediaQuery.of(context).size.height * 0.88,
          child: TaskDetailsSheet(task: task),
        ),
      ),
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

// Task Details Dialog Content
class TaskDetailsSheet extends ConsumerWidget {
  const TaskDetailsSheet({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    if (task.imageUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: Image.network(
                            task.imageUrl!,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (task.description != null && task.description!.isNotEmpty) ...[
                      Text(
                        'Описание',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: Colors.grey),
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
                                'Приоритет',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(color: Colors.grey),
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
                                'Статус',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        'Крайний срок',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            '${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}',
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Исполнитель',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    if (task.assignee != null)
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                Theme.of(context).primaryColor.withAlpha(50),
                            child: Text(
                              (task.assignee!.fullName ?? task.assignee!.email)[0]
                                  .toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(task.assignee!.fullName ?? 'Без имени'),
                              Text(
                                task.assignee!.email,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      const Row(
                        children: [
                          Icon(Icons.person_off_outlined, size: 18, color: Colors.grey),
                          SizedBox(width: 10),
                          Text(
                            'Не назначен',
                            style:
                                TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    _TaskLinksSection(taskId: task.id),
                    const SizedBox(height: 24),
                    _TaskDocumentsSection(taskId: task.id),
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: _TaskCommentsPanel(taskId: task.id),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить задачу'),
        content: const Text('Вы уверены, что хотите удалить эту задачу?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(kanbanProvider.notifier).deleteTask(task.id);
              Navigator.pop(context); // Close confirm dialog
              Navigator.pop(context); // Close bottom sheet
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _TaskCommentsPanel extends ConsumerStatefulWidget {
  const _TaskCommentsPanel({required this.taskId});

  final String taskId;

  @override
  ConsumerState<_TaskCommentsPanel> createState() => _TaskCommentsPanelState();
}

class _TaskCommentsPanelState extends ConsumerState<_TaskCommentsPanel> {
  final _controller = TextEditingController();
  int _refreshKey = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(kanbanProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Комментарии',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(_refreshKey),
            future: notifier.getTaskComments(widget.taskId),
            builder: (context, snapshot) {
              final comments = snapshot.data ?? [];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (comments.isEmpty) {
                return const Center(child: Text('Пока нет комментариев'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: comments.length,
                itemBuilder: (context, index) {
                  final c = comments[index];
                  final user = c['users'] as Map<String, dynamic>?;
                  final name = user?['full_name'] as String? ??
                      user?['email'] as String? ??
                      'Пользователь';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text((c['content'] as String?) ?? ''),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Написать комментарий...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () async {
                  final text = _controller.text.trim();
                  if (text.isEmpty) return;
                  await notifier.addTaskComment(taskId: widget.taskId, content: text);
                  _controller.clear();
                  if (mounted) {
                    setState(() => _refreshKey++);
                  }
                },
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskLinksSection extends ConsumerStatefulWidget {
  const _TaskLinksSection({required this.taskId});

  final String taskId;

  @override
  ConsumerState<_TaskLinksSection> createState() => _TaskLinksSectionState();
}

class _TaskLinksSectionState extends ConsumerState<_TaskLinksSection> {
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(kanbanProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Ссылки',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addLink(context),
              icon: const Icon(Icons.add_link),
              label: const Text('Добавить'),
            ),
          ],
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey(_refreshKey),
          future: notifier.getTaskLinks(widget.taskId),
          builder: (context, snapshot) {
            final links = snapshot.data ?? [];
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (links.isEmpty) {
              return const Text('Нет ссылок');
            }
            return Column(
              children: links.map((link) {
                final url = (link['url'] as String?) ?? '';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text((link['title'] as String?) ?? url),
                  subtitle: Text(url),
                  leading: const Icon(Icons.link),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      await notifier.deleteTaskLink(link['id'] as String);
                      if (mounted) setState(() => _refreshKey++);
                    },
                  ),
                  onTap: () async {
                    final uri = Uri.tryParse(url);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _addLink(BuildContext context) async {
    final notifier = ref.read(kanbanProvider.notifier);
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая ссылка'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'URL'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    if (ok == true && urlController.text.trim().isNotEmpty) {
      await notifier.addTaskLink(
        taskId: widget.taskId,
        title: titleController.text.trim().isEmpty ? null : titleController.text.trim(),
        url: urlController.text.trim(),
      );
      if (mounted) {
        setState(() => _refreshKey++);
      }
    }

    titleController.dispose();
    urlController.dispose();
  }
}

class _TaskDocumentsSection extends ConsumerStatefulWidget {
  const _TaskDocumentsSection({required this.taskId});

  final String taskId;

  @override
  ConsumerState<_TaskDocumentsSection> createState() => _TaskDocumentsSectionState();
}

class _TaskDocumentsSectionState extends ConsumerState<_TaskDocumentsSection> {
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(kanbanProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Документы',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _createDocument(context),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Создать'),
            ),
          ],
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          key: ValueKey(_refreshKey),
          future: notifier.getTaskDocuments(widget.taskId),
          builder: (context, snapshot) {
            final docs = snapshot.data ?? [];
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (docs.isEmpty) {
              return const Text('Нет документов');
            }
            return Column(
              children: docs.map((doc) {
                final updatedAt = DateTime.tryParse((doc['updated_at'] as String?) ?? '');
                final updatedBy = doc['updated_by'] as String?;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text((doc['title'] as String?) ?? 'Документ'),
                  subtitle: updatedAt == null
                      ? const Text('Нет данных об изменениях')
                      : FutureBuilder<String?>(
                          future: updatedBy == null
                              ? Future.value(null)
                              : SupabaseClientService.instance.rpc(
                                  functionName:
                                      'find_user_display_name_by_task_and_user',
                                  params: {
                                    'p_task_id': widget.taskId,
                                    'p_user_id': updatedBy,
                                  },
                                ).then((v) => v?.toString()),
                          builder: (context, snapshot) {
                            final updatedByName = snapshot.data ?? updatedBy;
                            return Text(
                              'Изменен: ${updatedAt.toLocal()}'
                              '${updatedByName != null ? ' • пользователь: $updatedByName' : ''}',
                            );
                          },
                        ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DocumentEditorScreen(
                          taskId: widget.taskId,
                          initialDocument: doc,
                        ),
                      ),
                    );
                    if (mounted) setState(() => _refreshKey++);
                  },
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _createDocument(BuildContext context) async {
    final notifier = ref.read(kanbanProvider.notifier);
    final titleController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать документ'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(labelText: 'Название'),
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

    if (ok == true && titleController.text.trim().isNotEmpty) {
      final doc = await notifier.createDocument(
        taskId: widget.taskId,
        title: titleController.text.trim(),
      );
      if (!mounted || !context.mounted || doc == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentEditorScreen(
            taskId: widget.taskId,
            initialDocument: doc,
          ),
        ),
      );
      if (mounted) setState(() => _refreshKey++);
    }

    titleController.dispose();
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

class _IssueTypeBadge extends StatelessWidget {
  const _IssueTypeBadge({required this.issueType});

  final TaskIssueType issueType;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (issueType) {
      TaskIssueType.epic => (Colors.purple, Icons.auto_awesome, 'ЭПИК'),
      TaskIssueType.story => (Colors.blue, Icons.menu_book_outlined, 'ИСТОРИЯ'),
      TaskIssueType.task => (Colors.teal, Icons.checklist_rtl_outlined, 'ЗАДАЧА'),
      TaskIssueType.bug => (Colors.red, Icons.bug_report_outlined, 'БАГ'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
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
      text = 'Просрочено';
    } else if (isToday) {
      color = Colors.orange;
      text = 'Сегодня';
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
      return 'К выполнению';
    case TaskStatus.inProgress:
      return 'В работе';
    case TaskStatus.review:
      return 'На ревью';
    case TaskStatus.done:
      return 'Готово';
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
