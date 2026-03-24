import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/services/supabase_client.dart';
import 'features/projects/domain/entities/project.dart';
import 'features/projects/providers/projects_provider.dart';
import 'features/projects/providers/boards_provider.dart';
import 'features/projects/presentation/pages/project_selection_screen.dart';
import 'features/analytics/presentation/pages/analytics_screen.dart';
import 'features/analytics/presentation/pages/global_analytics_screen.dart';
import 'shared/presentation/widgets/app_sidebar.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/presentation/widgets/auth_form.dart';
import 'features/auth/presentation/widgets/email_confirmation_screen.dart';
import 'features/kanban/presentation/widgets/kanban_board.dart';
import 'features/kanban/presentation/widgets/backlog_tab.dart';
import 'features/kanban/domain/entities/task.dart';
import 'features/kanban/providers/kanban_provider.dart';
import 'shared/presentation/widgets/loading_screen.dart';
import 'shared/presentation/widgets/notification_bell.dart';
import 'features/video_call/presentation/widgets/video_call_entry_dialog.dart';
import 'features/video_call/presentation/widgets/video_call_room_screen.dart';
import 'features/chat/presentation/widgets/board_chat_button.dart';

class SupabaseInitializationState {
  const SupabaseInitializationState({
    this.isInitialized = false,
    this.error,
  });

  final bool isInitialized;
  final String? error;
}

final supabaseInitializationProvider = Provider<SupabaseInitializationState>((ref) {
  return const SupabaseInitializationState();
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supabaseService = SupabaseClientService.instance;

  try {
    await supabaseService.initialize();
  } catch (_) {
    // Initialization error is stored in the service; we'll show fallback UI
  }

  runApp(ProviderScope(overrides: [
    supabaseInitializationProvider.overrideWithValue(
      SupabaseInitializationState(
        isInitialized: supabaseService.isInitialized,
        error: supabaseService.initializationError,
      ),
    ),
  ], child: const MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initState = ref.watch(supabaseInitializationProvider);
    final authState = ref.watch(authNotifierProvider);
    final selectedProject = ref.watch(selectedProjectProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: _buildHome(initState, authState, selectedProject, ref),
    );
  }

  Widget _buildHome(
    SupabaseInitializationState initState,
    AppAuthState authState,
    Project? selectedProject,
    WidgetRef ref,
  ) {
    if (!initState.isInitialized) {
      return _InitializationErrorScreen(error: initState.error);
    }

    // After successful signup Supabase may clear session until email is confirmed.
    // Show confirmation screen even if `authState.user` becomes null.
    if (authState.pendingEmailConfirmationEmail != null) {
      return EmailConfirmationScreen(
        email: authState.pendingEmailConfirmationEmail!,
      );
    }

    if (authState.isLoading) {
      return const LoadingScreen();
    }

    if (authState.user == null) {
      return const AuthForm();
    }

    if (selectedProject == null) {
      return const ProjectSelectionScreen();
    }

    return KanbanBoardWrapper(selectedProject: selectedProject);
  }
}

class KanbanBoardWrapper extends StatelessWidget {
  const KanbanBoardWrapper({super.key, required this.selectedProject});

  final Project selectedProject;

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, child) {
      final kanbanState = ref.watch(kanbanProvider);
      final currentUserId = SupabaseClientService.instance.currentUserId;
      final isOwner = currentUserId != null && selectedProject.ownerId == currentUserId;
      final boardsState = ref.watch(boardsProvider);
      final boardsNotifier = ref.read(boardsProvider.notifier);
      final authState = ref.watch(authNotifierProvider);
      final collaborationBoardId = boardsState.selectedBoardId ??
          (boardsState.boards.isNotEmpty ? boardsState.boards.first.id : null);

      final loadedForCurrentProject =
          boardsState.boards.isNotEmpty && boardsState.boards.first.projectId == selectedProject.id;
      if (!boardsState.isLoading &&
          (!loadedForCurrentProject || boardsState.boards.isEmpty)) {
        Future.microtask(() => boardsNotifier.loadBoards(selectedProject.id));
      }
      
      final isDesktop = MediaQuery.of(context).size.width >= 1200;

      final scaffoldKey = GlobalKey<ScaffoldState>();

      return DefaultTabController(
        length: 7,
        child: Scaffold(
          key: scaffoldKey,
          backgroundColor: const Color(0xFF1E1E24),
          drawer: isDesktop ? null : const AppSidebar(),
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(62),
            child: _ProjectTopBar(
              projectName: selectedProject.name,
              onCreatePressed: () async {
                final created = await showDialog<bool>(
                  context: context,
                  builder: (_) => _QuickCreateIssueDialog(
                    projectId: selectedProject.id,
                    boardId: boardsState.selectedBoardId,
                  ),
                );
                if (created == true) {
                  await ref.read(kanbanProvider.notifier).loadTasks(
                        selectedProject.id,
                        boardId: boardsState.selectedBoardId,
                      );
                }
              },
              onOpenDrawer: isDesktop
                  ? null
                  : () => scaffoldKey.currentState?.openDrawer(),
              actions: [
                const NotificationBell(),
                const SizedBox(width: 8),
                BoardChatButton(boardId: collaborationBoardId),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.video_call_outlined),
                  tooltip: 'Видеозвонок проекта',
                  onPressed: () async {
                final boardId = collaborationBoardId;
                if (boardId == null) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Создайте доску для видеозвонка проекта')),
                  );
                  return;
                }

                final displayName = authState.user?.fullName ??
                    authState.user?.email ??
                    'Пользователь';

                try {
                  final res = await showVideoCallEntryDialog(
                    context: context,
                    boardId: boardId,
                    displayName: displayName,
                  );
                  if (res == null) return;
                  if (!context.mounted) return;

                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoCallRoomScreen(
                        boardId: boardId,
                        roomId: res.roomId,
                        audioDeviceId: res.audioDeviceId,
                        videoDeviceId: res.videoDeviceId,
                      ),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка звонка: $e')),
                  );
                }
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Обновить',
                  onPressed: () => ref.read(kanbanProvider.notifier).loadTasks(
                        selectedProject.id,
                        boardId: boardsState.selectedBoardId,
                      ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<int>(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Управление проектом',
                  itemBuilder: (context) => [
                    if (!isOwner)
                      const PopupMenuItem<int>(
                        value: 1,
                        child: Text('Покинуть проект'),
                      ),
                    if (isOwner)
                      const PopupMenuItem<int>(
                        value: 2,
                        child: Text('Удалить проект'),
                      ),
                  ],
                  onSelected: (value) async {
                final notifier = ref.read(projectsProvider.notifier);

                try {
                  if (value == 1) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Покинуть проект'),
                        content: const Text('Вы уверены, что хотите покинуть проект?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Отмена'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Покинуть'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    await notifier.leaveProject(selectedProject.id);
                  } else if (value == 2) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Удалить проект'),
                        content: const Text('Удаление проекта необратимо. Продолжить?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Отмена'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    await notifier.deleteProject(selectedProject.id);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
                  }
                }
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          body: Row(
            children: [
              if (isDesktop)
                const SizedBox(
                  width: 280,
                  child: _JiraLikeLeftPanel(),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: const Color(0xFF252830),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white70,
                        indicatorColor: const Color(0xFF4C9AFF),
                        tabs: const [
                          Tab(text: 'Сводка'),
                          Tab(text: 'Бэклог'),
                          Tab(text: 'Доска'),
                          Tab(text: 'Хронология'),
                          Tab(text: 'Страницы'),
                          Tab(text: 'Формы'),
                          Tab(icon: Icon(Icons.add)),
                        ],
                      ),
                    ),
                    if (kanbanState.isDemoData)
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.amber[100],
                          border: Border(bottom: BorderSide(color: Colors.amber[300]!, width: 1)),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                kanbanState.demoMessage ??
                                    'Демо-режим: проверьте инструкции по настройке project_members в fix_rls.sql.',
                                style: TextStyle(
                                  color: Colors.amber[900],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _ProjectSummaryTab(kanbanState: kanbanState),
                          BacklogTab(
                            projectId: selectedProject.id,
                            boardId: boardsState.selectedBoardId,
                          ),
                          Column(
                            children: [
                              Container(
                                color: const Color(0xFF252830),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: TextField(
                                        decoration: InputDecoration(
                                          hintText: 'Поиск на доске',
                                          isDense: true,
                                          prefixIcon: Icon(Icons.search, size: 18),
                                          border: OutlineInputBorder(),
                                          filled: true,
                                          fillColor: Color(0xFF2B2D31),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (boardsState.boards.isNotEmpty)
                                      DropdownButtonHideUnderline(
                                        child: DropdownButton<String?>(
                                          value: boardsState.selectedBoardId,
                                          dropdownColor: const Color(0xFF2B2D31),
                                          hint: const Text('Основная доска'),
                                          items: [
                                            const DropdownMenuItem<String?>(
                                              value: null,
                                              child: Text('Основная доска'),
                                            ),
                                            ...boardsState.boards.map((b) {
                                              final location = [
                                                if (b.departmentName != null) b.departmentName!,
                                                if (b.folderName != null) b.folderName!,
                                              ].join(' / ');
                                              final label =
                                                  location.isEmpty ? b.name : '$location / ${b.name}';
                                              return DropdownMenuItem<String?>(
                                                value: b.id,
                                                child: Text(label),
                                              );
                                            }),
                                          ],
                                          onChanged: (value) {
                                            boardsNotifier.selectBoard(value);
                                            ref.read(kanbanProvider.notifier).loadTasks(
                                                  selectedProject.id,
                                                  boardId: value,
                                                );
                                          },
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () {},
                                      icon: const Icon(Icons.filter_list),
                                      label: const Text('Фильтр'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () {},
                                      icon: const Icon(Icons.view_stream),
                                      label: const Text('Группировать'),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  color: const Color(0xFF1E1E24),
                                  child: KanbanBoardWidget(
                                    projectId: selectedProject.id,
                                    boardId: boardsState.selectedBoardId,
                                    onNavigateToBacklog: () => DefaultTabController.of(context).animateTo(1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _TimelineTab(
                            kanbanState: kanbanState,
                            projectId: selectedProject.id,
                          ),
                          _PagesTab(projectId: selectedProject.id),
                          _FormsTab(projectId: selectedProject.id),
                          const _ProjectTabPlaceholder(title: 'Добавить вид', subtitle: 'В разработке'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _ProjectSummaryTab extends StatelessWidget {
  const _ProjectSummaryTab({required this.kanbanState});

  final KanbanState kanbanState;

  @override
  Widget build(BuildContext context) {
    final total = kanbanState.tasksByStatus.values.fold<int>(0, (sum, list) => sum + list.length);
    final todo = kanbanState.tasksByStatus[TaskStatus.todo]?.length ?? 0;
    final inProgress = kanbanState.tasksByStatus[TaskStatus.inProgress]?.length ?? 0;
    final review = kanbanState.tasksByStatus[TaskStatus.review]?.length ?? 0;
    final done = kanbanState.tasksByStatus[TaskStatus.done]?.length ?? 0;
    final completion = total == 0 ? 0.0 : done / total;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Сводка проекта',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _MetricCard(title: 'Всего задач', value: '$total')),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(title: 'В работе', value: '$inProgress')),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(title: 'На ревью', value: '$review')),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(title: 'Готово', value: '$done')),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Прогресс спринта', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: completion, minHeight: 10),
                const SizedBox(height: 8),
                Text(
                  '${(completion * 100).toStringAsFixed(0)}% выполнено • К выполнению: $todo',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _TimelineTab extends ConsumerWidget {
  const _TimelineTab({
    required this.kanbanState,
    required this.projectId,
  });

  final KanbanState kanbanState;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(kanbanProvider.notifier);
    final visibleTasks = kanbanState.tasksByStatus.values.expand((list) => list).toList();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: notifier.getProjectSprints(projectId),
      builder: (context, snapshot) {
        final sprints = snapshot.data ?? [];
        final sortedSprints = [...sprints]
          ..sort((a, b) {
            final aDate = DateTime.tryParse((a['start_date'] as String?) ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = DateTime.tryParse((b['start_date'] as String?) ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return aDate.compareTo(bDate);
          });

        final tasksBySprint = <String, List<Task>>{};
        final backlogTasks = <Task>[];
        for (final task in visibleTasks) {
          if (task.sprintId == null) {
            backlogTasks.add(task);
          } else {
            tasksBySprint.putIfAbsent(task.sprintId!, () => []);
            tasksBySprint[task.sprintId!]!.add(task);
          }
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Хронология и roadmap',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              'Показывает спринты, сроки и прогресс по задачам.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            if (sortedSprints.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Спринты пока не созданы. Добавьте спринт во вкладке Бэклог.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ...sortedSprints.map((sprint) {
              final sprintId = sprint['id'] as String?;
              final sprintName = (sprint['name'] as String?) ?? 'Спринт';
              final status = (sprint['status'] as String?) ?? 'planned';
              final startDate = DateTime.tryParse((sprint['start_date'] as String?) ?? '');
              final endDate = DateTime.tryParse((sprint['end_date'] as String?) ?? '');
              final sprintTasks = sprintId == null ? <Task>[] : (tasksBySprint[sprintId] ?? <Task>[]);
              final doneCount =
                  sprintTasks.where((task) => task.status == TaskStatus.done).length;
              final progress = sprintTasks.isEmpty ? 0.0 : doneCount / sprintTasks.length;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                sprintName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _SprintStatusBadge(status: status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Период: ${_formatDate(startDate)} - ${_formatDate(endDate)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(value: progress, minHeight: 8),
                        const SizedBox(height: 8),
                        Text(
                          'Задач: ${sprintTasks.length} • Готово: $doneCount',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        if (sprintTasks.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: sprintTasks
                                .take(6)
                                .map(
                                  (task) => Chip(
                                    label: Text(task.title),
                                    avatar: Icon(
                                      task.status == TaskStatus.done
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      size: 16,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Бэклог без спринта',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Задач: ${backlogTasks.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SprintStatusBadge extends StatelessWidget {
  const _SprintStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active' => ('Активный', Colors.green),
      'completed' => ('Завершен', Colors.blueGrey),
      _ => ('Запланирован', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return 'не задан';
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

class _PagesTab extends ConsumerStatefulWidget {
  const _PagesTab({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_PagesTab> createState() => _PagesTabState();
}

class _PagesTabState extends ConsumerState<_PagesTab> {
  int _reloadKey = 0;

  void _refresh() => setState(() => _reloadKey++);

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(kanbanProvider.notifier);
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_reloadKey),
      future: notifier.getProjectPages(widget.projectId),
      builder: (context, snapshot) {
        final pages = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Страницы',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final created = await _showPageDialog(context, notifier);
                    if (created) _refresh();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Новая страница'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (pages.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Страницы пока не созданы.', style: TextStyle(color: Colors.white70)),
                ),
              ),
            ...pages.map((page) {
              final title = (page['title'] as String?) ?? 'Без названия';
              final content = (page['content'] as String?) ?? '';
              return Card(
                child: ListTile(
                  title: Text(title, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    content.isEmpty ? 'Пустая страница' : content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final updated = await _showPageDialog(
                            context,
                            notifier,
                            page: page,
                          );
                          if (updated) _refresh();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () async {
                          await notifier.deleteProjectPage(page['id'] as String);
                          _refresh();
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<bool> _showPageDialog(
    BuildContext context,
    KanbanNotifier notifier, {
    Map<String, dynamic>? page,
  }) async {
    final titleController = TextEditingController(text: page?['title'] as String? ?? '');
    final contentController = TextEditingController(text: page?['content'] as String? ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(page == null ? 'Новая страница' : 'Редактировать страницу'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: contentController,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Контент'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить')),
        ],
      ),
    );

    if (save == true && titleController.text.trim().isNotEmpty) {
      if (page == null) {
        final created = await notifier.createProjectPage(
          projectId: widget.projectId,
          title: titleController.text.trim(),
          content: contentController.text.trim(),
        );
        return created != null;
      }
      final updated = await notifier.updateProjectPage(
        id: page['id'] as String,
        title: titleController.text.trim(),
        content: contentController.text.trim(),
      );
      return updated != null;
    }
    return false;
  }
}

class _FormsTab extends ConsumerStatefulWidget {
  const _FormsTab({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_FormsTab> createState() => _FormsTabState();
}

class _FormsTabState extends ConsumerState<_FormsTab> {
  int _reloadKey = 0;

  void _refresh() => setState(() => _reloadKey++);

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(kanbanProvider.notifier);
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_reloadKey),
      future: notifier.getProjectForms(widget.projectId),
      builder: (context, snapshot) {
        final forms = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Формы',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final created = await _showFormDialog(context, notifier);
                    if (created) _refresh();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Новая форма'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (forms.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Формы пока не созданы.', style: TextStyle(color: Colors.white70)),
                ),
              ),
            ...forms.map((form) {
              final title = (form['title'] as String?) ?? 'Без названия';
              final description = (form['description'] as String?) ?? '';
              final isActive = (form['is_active'] as bool?) ?? true;
              return Card(
                child: ListTile(
                  title: Text(title, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    description.isEmpty ? 'Без описания' : description,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: isActive
                            ? () async {
                                final submitted = await _showFormSubmitDialog(
                                  context,
                                  notifier,
                                  form: form,
                                );
                                if (submitted) _refresh();
                              }
                            : null,
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Заполнить'),
                      ),
                      Switch(
                        value: isActive,
                        onChanged: (value) async {
                          await notifier.updateProjectForm(
                            id: form['id'] as String,
                            title: title,
                            description: description.isEmpty ? null : description,
                            isActive: value,
                          );
                          _refresh();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final updated = await _showFormDialog(
                            context,
                            notifier,
                            form: form,
                          );
                          if (updated) _refresh();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () async {
                          await notifier.deleteProjectForm(form['id'] as String);
                          _refresh();
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<bool> _showFormDialog(
    BuildContext context,
    KanbanNotifier notifier, {
    Map<String, dynamic>? form,
  }) async {
    final boardsState = ref.read(boardsProvider);
    final projectsNotifier = ref.read(projectsProvider.notifier);
    final members = await projectsNotifier.getProjectMembers(widget.projectId);
    final sprints = await notifier.getProjectSprints(widget.projectId);
    if (!context.mounted) return false;
    final titleController = TextEditingController(text: form?['title'] as String? ?? '');
    final descriptionController = TextEditingController(text: form?['description'] as String? ?? '');
    final issueDefaults = (form?['issue_defaults'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v),
        ) ??
        <String, dynamic>{};
    final existingFields = ((form?['fields'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
    final fieldsData = existingFields
        .map(
          (field) => <String, dynamic>{
            'id': (field['id'] as String?) ?? '',
            'label': (field['label'] as String?) ?? '',
            'type': (field['type'] as String?) ?? 'text',
            'required': (field['required'] as bool?) ?? false,
          },
        )
        .toList();
    var defaultIssueType = issueDefaults['issue_type']?.toString() ?? TaskIssueType.task.name;
    var defaultPriority = issueDefaults['priority']?.toString() ?? TaskPriority.medium.name;
    String? defaultBoardId = issueDefaults['board_id']?.toString();
    String? defaultSprintId = issueDefaults['sprint_id']?.toString();
    String? defaultAssigneeId = issueDefaults['assignee_id']?.toString();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(form == null ? 'Новая форма' : 'Редактировать форму'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descriptionController,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Описание'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Поля формы',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            fieldsData.add({
                              'id': '',
                              'label': '',
                              'type': 'text',
                              'required': false,
                            });
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить поле'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (fieldsData.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Поля еще не добавлены.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ...fieldsData.asMap().entries.map((entry) {
                    final index = entry.key;
                    final field = entry.value;
                    final idController = TextEditingController(text: field['id'] as String? ?? '');
                    final labelController =
                        TextEditingController(text: field['label'] as String? ?? '');
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: idController,
                                    decoration: const InputDecoration(
                                      labelText: 'Ключ (id)',
                                      hintText: 'например: title',
                                    ),
                                    onChanged: (value) => field['id'] = value,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: labelController,
                                    decoration: const InputDecoration(
                                      labelText: 'Название поля',
                                      hintText: 'например: Название',
                                    ),
                                    onChanged: (value) => field['label'] = value,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: field['type'] as String? ?? 'text',
                                    decoration: const InputDecoration(labelText: 'Тип'),
                                    items: const [
                                      DropdownMenuItem(value: 'text', child: Text('Текст')),
                                      DropdownMenuItem(
                                        value: 'multiline',
                                        child: Text('Многострочный текст'),
                                      ),
                                      DropdownMenuItem(value: 'number', child: Text('Число')),
                                      DropdownMenuItem(value: 'date', child: Text('Дата')),
                                      DropdownMenuItem(value: 'select', child: Text('Список')),
                                    ],
                                    onChanged: (value) => setDialogState(() {
                                      field['type'] = value ?? 'text';
                                      if (field['type'] == 'select' && field['options'] == null) {
                                        field['options'] = <String>[];
                                      }
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: (field['required'] as bool?) ?? false,
                                        onChanged: (value) => setDialogState(
                                          () => field['required'] = value ?? false,
                                        ),
                                      ),
                                      const Text('Обязательное'),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                        onPressed: () {
                                          setDialogState(() => fieldsData.removeAt(index));
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if ((field['type'] as String?) == 'select') ...[
                              const SizedBox(height: 8),
                              _SelectOptionsEditor(
                                options: (field['options'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
                                onChanged: (options) => setDialogState(() => field['options'] = options),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Создание issue по умолчанию',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: defaultIssueType,
                          decoration: const InputDecoration(labelText: 'Тип issue'),
                          items: const [
                            DropdownMenuItem(value: 'epic', child: Text('Эпик')),
                            DropdownMenuItem(value: 'story', child: Text('История')),
                            DropdownMenuItem(value: 'task', child: Text('Задача')),
                            DropdownMenuItem(value: 'bug', child: Text('Баг')),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => defaultIssueType = value ?? 'task'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: defaultPriority,
                          decoration: const InputDecoration(labelText: 'Приоритет'),
                          items: const [
                            DropdownMenuItem(value: 'low', child: Text('Низкий')),
                            DropdownMenuItem(value: 'medium', child: Text('Средний')),
                            DropdownMenuItem(value: 'high', child: Text('Высокий')),
                            DropdownMenuItem(value: 'urgent', child: Text('Срочный')),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => defaultPriority = value ?? 'medium'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: defaultBoardId,
                    decoration: const InputDecoration(labelText: 'Доска по умолчанию'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Текущая доска'),
                      ),
                      ...boardsState.boards.map(
                        (board) => DropdownMenuItem<String?>(
                          value: board.id,
                          child: Text(board.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() => defaultBoardId = value),
                  ),
                  if (defaultBoardId != null &&
                      !boardsState.boards.any((board) => board.id == defaultBoardId))
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Выбранная доска недоступна. Будет использована текущая доска.',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: defaultSprintId,
                    decoration: const InputDecoration(labelText: 'Спринт по умолчанию'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Активный/без спринта'),
                      ),
                      ...sprints.map(
                        (s) => DropdownMenuItem<String?>(
                          value: s['id'] as String?,
                          child: Text((s['name'] as String?) ?? 'Спринт'),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() => defaultSprintId = value),
                  ),
                  if (defaultSprintId != null &&
                      !sprints.any((s) => s['id']?.toString() == defaultSprintId))
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Выбранный спринт недоступен. Будет использован активный/без спринта.',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: defaultAssigneeId,
                    decoration: const InputDecoration(labelText: 'Исполнитель по умолчанию'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Не назначен'),
                      ),
                      ...members.map((m) {
                        final user = m['users'] as Map<String, dynamic>?;
                        final label = user?['full_name'] as String? ??
                            user?['email'] as String? ??
                            'Пользователь';
                        return DropdownMenuItem<String?>(
                          value: m['user_id'] as String?,
                          child: Text(label),
                        );
                      }),
                    ],
                    onChanged: (value) => setDialogState(() => defaultAssigneeId = value),
                  ),
                  if (defaultAssigneeId != null &&
                      !members.any((m) => m['user_id']?.toString() == defaultAssigneeId))
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Выбранный исполнитель недоступен. Задача будет без исполнителя.',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сохранить')),
          ],
        ),
      ),
    );

    if (save == true && titleController.text.trim().isNotEmpty) {
      final parsedFields = fieldsData
          .where((f) => (f['id'] as String?)?.trim().isNotEmpty ?? false)
          .map(
            (f) => <String, dynamic>{
              'id': (f['id'] as String).trim(),
              'label': ((f['label'] as String?)?.trim().isEmpty ?? true)
                  ? (f['id'] as String).trim()
                  : (f['label'] as String).trim(),
              'type': f['type'] ?? 'text',
              'required': f['required'] ?? false,
              if ((f['type'] as String?) == 'select')
                'options': (f['options'] as List?)?.map((e) => e.toString()).where((o) => o.trim().isNotEmpty).toList() ?? <String>[],
            },
          )
          .toList();

      if (form == null) {
        final created = await notifier.createProjectForm(
          projectId: widget.projectId,
          title: titleController.text.trim(),
          description: descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
          fields: parsedFields,
          issueDefaults: {
            'issue_type': defaultIssueType,
            'priority': defaultPriority,
            'board_id': defaultBoardId,
            'sprint_id': defaultSprintId,
            'assignee_id': defaultAssigneeId,
          },
        );
        return created != null;
      }
      final updated = await notifier.updateProjectForm(
        id: form['id'] as String,
        title: titleController.text.trim(),
        description: descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
        fields: parsedFields,
        issueDefaults: {
          'issue_type': defaultIssueType,
          'priority': defaultPriority,
          'board_id': defaultBoardId,
          'sprint_id': defaultSprintId,
          'assignee_id': defaultAssigneeId,
        },
        isActive: form['is_active'] as bool? ?? true,
      );
      return updated != null;
    }
    return false;
  }

  Future<bool> _showFormSubmitDialog(
    BuildContext context,
    KanbanNotifier notifier, {
    required Map<String, dynamic> form,
  }) async {
    final fields = (form['fields'] as List?)?.whereType<Map>().map(
          (e) => e.map((k, v) => MapEntry(k.toString(), v)),
        ).toList() ??
        <Map<String, dynamic>>[];

    final controllers = <String, TextEditingController>{};
    for (final field in fields) {
      final id = (field['id'] as String?) ?? '';
      if (id.isEmpty) continue;
      controllers[id] = TextEditingController();
    }

    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Заполнить форму: ${(form['title'] as String?) ?? ''}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (fields.isEmpty)
                  const Text(
                    'У формы нет полей. Добавьте поля в настройках формы.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ...fields.map((field) {
                  final id = (field['id'] as String?) ?? '';
                  final label = (field['label'] as String?) ?? id;
                  final required = (field['required'] as bool?) ?? false;
                  final type = (field['type'] as String?) ?? 'text';
                  final options = (field['options'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
                  final controller = controllers[id] ?? TextEditingController();
                  controllers[id] = controller;

                  if (type == 'multiline') {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: controller,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: required ? '$label *' : label,
                        ),
                      ),
                    );
                  }
                  if (type == 'date') {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: controller,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: required ? '$label *' : label,
                          suffixIcon: const Icon(Icons.calendar_today_outlined),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            controller.text =
                                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                          }
                        },
                      ),
                    );
                  }
                  if (type == 'select') {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DropdownButtonFormField<String>(
                        initialValue: controller.text.isEmpty ? null : controller.text,
                        decoration: InputDecoration(labelText: required ? '$label *' : label),
                        items: options
                            .map(
                              (option) => DropdownMenuItem<String>(
                                value: option,
                                child: Text(option),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => controller.text = value ?? '',
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: controller,
                      keyboardType: type == 'number' ? TextInputType.number : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: required ? '$label *' : label,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Отправить')),
        ],
      ),
    );

    if (send == true) {
      final answers = <String, dynamic>{};
      for (final field in fields) {
        final id = (field['id'] as String?) ?? '';
        if (id.isEmpty) continue;
        final required = (field['required'] as bool?) ?? false;
        final type = (field['type'] as String?) ?? 'text';
        final value = controllers[id]?.text.trim() ?? '';
        if (required && value.isEmpty) {
          if (!context.mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Заполните обязательное поле: ${field['label'] ?? id}')),
          );
          return false;
        }
        if (value.isNotEmpty && type == 'number' && num.tryParse(value) == null) {
          if (!context.mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Поле "${field['label'] ?? id}" должно быть числом')),
          );
          return false;
        }
        if (value.isNotEmpty && type == 'date' && DateTime.tryParse(value) == null) {
          if (!context.mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Поле "${field['label'] ?? id}" должно быть датой')),
          );
          return false;
        }
        answers[id] = value;
      }

      final submitted = await notifier.submitProjectForm(
        projectId: widget.projectId,
        formId: form['id'] as String,
        answers: answers,
        issueDefaults: (form['issue_defaults'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v),
            ) ??
            const {},
      );
      if (submitted != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Форма отправлена, задача создана.')),
        );
        return true;
      }
    }
    return false;
  }
}

class _SelectOptionsEditor extends StatefulWidget {
  const _SelectOptionsEditor({
    required this.options,
    required this.onChanged,
  });

  final List<String> options;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_SelectOptionsEditor> createState() => _SelectOptionsEditorState();
}

class _SelectOptionsEditorState extends State<_SelectOptionsEditor> {
  late List<String> _options;
  final TextEditingController _newOptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _options = [...widget.options];
  }

  @override
  void didUpdateWidget(covariant _SelectOptionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options != widget.options) {
      _options = [...widget.options];
    }
  }

  @override
  void dispose() {
    _newOptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Опции списка',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _options
              .map(
                (option) => Chip(
                  label: Text(option),
                  onDeleted: () {
                    setState(() => _options.remove(option));
                    widget.onChanged(_options);
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newOptionController,
                decoration: const InputDecoration(
                  labelText: 'Новая опция',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: () {
                final value = _newOptionController.text.trim();
                if (value.isEmpty) return;
                setState(() => _options.add(value));
                widget.onChanged(_options);
                _newOptionController.clear();
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProjectTopBar extends StatelessWidget {
  const _ProjectTopBar({
    required this.projectName,
    required this.onCreatePressed,
    this.onOpenDrawer,
    required this.actions,
  });

  final String projectName;
  final VoidCallback onCreatePressed;
  final VoidCallback? onOpenDrawer;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF252830),
      foregroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 12,
      title: Row(
        children: [
          if (onOpenDrawer != null)
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: onOpenDrawer,
            ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF4C9AFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.dashboard_customize, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(
            projectName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFF2B2D31),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onCreatePressed,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Создать'),
          ),
        ],
      ),
      actions: actions,
    );
  }
}

class _JiraLikeLeftPanel extends ConsumerWidget {
  const _JiraLikeLeftPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsState = ref.watch(projectsProvider);
    final selectedProject = ref.watch(selectedProjectProvider);
    final projectsNotifier = ref.read(projectsProvider.notifier);
    final recentProjects = projectsState.projects.take(3).toList();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF252830),
        border: Border(right: BorderSide(color: Color(0xFF2F343F))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: ListView(
        children: [
          const _PanelHeader(title: 'Для вас'),
          _PanelItem(
            icon: Icons.home_outlined,
            title: 'Все проекты',
            onTap: () => projectsNotifier.selectProject(null),
          ),
          const SizedBox(height: 12),
          const _PanelHeader(title: 'Недавние'),
          if (recentProjects.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('Нет проектов', style: TextStyle(color: Colors.white54)),
            ),
          ...recentProjects.map(
            (project) => _PanelItem(
              icon: Icons.folder_outlined,
              title: project.name,
              selected: selectedProject?.id == project.id,
              onTap: () => projectsNotifier.selectProject(project.id),
            ),
          ),
          const SizedBox(height: 12),
          const _PanelHeader(title: 'Другие разделы'),
          _PanelItem(
            icon: Icons.insights_outlined,
            title: 'Отчеты',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
              );
            },
          ),
          _PanelItem(
            icon: Icons.auto_graph_outlined,
            title: 'Аналитика',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GlobalAnalyticsScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          const _PanelHeader(title: 'Рекомендуется'),
          const _PanelItem(icon: Icons.lightbulb_outline, title: 'Планы релизов'),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white54,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PanelItem extends StatelessWidget {
  const _PanelItem({
    required this.icon,
    required this.title,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF4C9AFF).withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        onTap: onTap,
        dense: true,
        horizontalTitleGap: 10,
        leading: Icon(icon, color: Colors.white70, size: 18),
        title: Text(
          title,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ProjectTabPlaceholder extends StatelessWidget {
  const _ProjectTabPlaceholder({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _QuickCreateIssueDialog extends ConsumerStatefulWidget {
  const _QuickCreateIssueDialog({
    required this.projectId,
    required this.boardId,
  });

  final String projectId;
  final String? boardId;

  @override
  ConsumerState<_QuickCreateIssueDialog> createState() =>
      _QuickCreateIssueDialogState();
}

class _QuickCreateIssueDialogState extends ConsumerState<_QuickCreateIssueDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  TaskIssueType _issueType = TaskIssueType.task;
  TaskPriority _priority = TaskPriority.medium;
  String? _assigneeId;
  String? _sprintId;
  String? _epicId;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kanbanNotifier = ref.read(kanbanProvider.notifier);
    final projectsNotifier = ref.read(projectsProvider.notifier);

    return AlertDialog(
      title: const Text('Быстрое создание задачи'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Название'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Введите название' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Описание'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<TaskIssueType>(
                        initialValue: _issueType,
                        decoration: const InputDecoration(labelText: 'Тип'),
                        items: const [
                          DropdownMenuItem(value: TaskIssueType.epic, child: Text('Эпик')),
                          DropdownMenuItem(value: TaskIssueType.story, child: Text('История')),
                          DropdownMenuItem(value: TaskIssueType.task, child: Text('Задача')),
                          DropdownMenuItem(value: TaskIssueType.bug, child: Text('Баг')),
                        ],
                        onChanged: (value) =>
                            setState(() => _issueType = value ?? TaskIssueType.task),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<TaskPriority>(
                        initialValue: _priority,
                        decoration: const InputDecoration(labelText: 'Приоритет'),
                        items: const [
                          DropdownMenuItem(value: TaskPriority.low, child: Text('Низкий')),
                          DropdownMenuItem(value: TaskPriority.medium, child: Text('Средний')),
                          DropdownMenuItem(value: TaskPriority.high, child: Text('Высокий')),
                          DropdownMenuItem(value: TaskPriority.urgent, child: Text('Срочный')),
                        ],
                        onChanged: (value) =>
                            setState(() => _priority = value ?? TaskPriority.medium),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: projectsNotifier.getProjectMembers(widget.projectId),
                  builder: (context, snapshot) {
                    final members = snapshot.data ?? [];
                    return DropdownButtonFormField<String?>(
                      initialValue: _assigneeId,
                      decoration: const InputDecoration(labelText: 'Исполнитель'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Не назначен')),
                        ...members.map((m) {
                          final user = m['users'] as Map<String, dynamic>?;
                          final label = user?['full_name'] as String? ??
                              user?['email'] as String? ??
                              'Пользователь';
                          return DropdownMenuItem<String?>(
                            value: m['user_id'] as String?,
                            child: Text(label),
                          );
                        }),
                      ],
                      onChanged: (value) => setState(() => _assigneeId = value),
                    );
                  },
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: kanbanNotifier.getProjectSprints(widget.projectId),
                  builder: (context, snapshot) {
                    final sprints = snapshot.data ?? [];
                    return DropdownButtonFormField<String?>(
                      initialValue: _sprintId,
                      decoration: const InputDecoration(labelText: 'Спринт'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Без спринта'),
                        ),
                        ...sprints.map(
                          (s) => DropdownMenuItem<String?>(
                            value: s['id'] as String?,
                            child: Text((s['name'] as String?) ?? 'Спринт'),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _sprintId = value),
                    );
                  },
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<Task>>(
                  future: kanbanNotifier.getProjectEpics(
                    projectId: widget.projectId,
                    boardId: widget.boardId,
                  ),
                  builder: (context, snapshot) {
                    final epics = snapshot.data ?? [];
                    return DropdownButtonFormField<String?>(
                      initialValue: _epicId,
                      decoration: const InputDecoration(labelText: 'Эпик'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Без эпика'),
                        ),
                        ...epics.map(
                          (e) => DropdownMenuItem<String?>(
                            value: e.id,
                            child: Text(e.title),
                          ),
                        ),
                      ],
                      onChanged: _issueType == TaskIssueType.epic
                          ? null
                          : (value) => setState(() => _epicId = value),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  final navigator = Navigator.of(context);
                  setState(() => _isSubmitting = true);
                  await kanbanNotifier.createTask(
                    title: _titleController.text.trim(),
                    description: _descriptionController.text.trim(),
                    assigneeId: _assigneeId,
                    priority: _priority,
                    issueType: _issueType,
                    epicId: _issueType == TaskIssueType.epic ? null : _epicId,
                    sprintId: _sprintId,
                  );
                  if (!mounted) return;
                  navigator.pop(true);
                },
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Создать'),
        ),
      ],
    );
  }
}

class _InitializationErrorScreen extends StatelessWidget {
  const _InitializationErrorScreen({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              const Text(
                'Supabase не инициализирован',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                error ?? 'Проверьте Supabase URL и anon key в app_constants.dart',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Показаны демо-данные. После исправления конфигурации перезапустите приложение.',
                style: TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const MyApp()),
                    (_) => false,
                  );
                },
                child: const Text('Повторить попытку'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
