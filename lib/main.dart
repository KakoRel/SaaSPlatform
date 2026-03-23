import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/services/supabase_client.dart';
import 'features/projects/domain/entities/project.dart';
import 'features/projects/providers/projects_provider.dart';
import 'features/projects/providers/boards_provider.dart';
import 'features/projects/presentation/pages/project_selection_screen.dart';
import 'features/projects/presentation/pages/project_structure_screen.dart';
import 'shared/presentation/widgets/app_sidebar.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/presentation/widgets/auth_form.dart';
import 'features/auth/presentation/widgets/email_confirmation_screen.dart';
import 'features/kanban/presentation/widgets/kanban_board.dart';
import 'features/kanban/providers/kanban_provider.dart';
import 'shared/presentation/widgets/loading_screen.dart';
import 'shared/presentation/widgets/notification_bell.dart';
import 'features/video_call/presentation/widgets/video_call_entry_dialog.dart';
import 'features/video_call/presentation/widgets/video_call_room_screen.dart';

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
      themeMode: ThemeMode.light,
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

      final loadedForCurrentProject =
          boardsState.boards.isNotEmpty && boardsState.boards.first.projectId == selectedProject.id;
      if (!boardsState.isLoading &&
          (!loadedForCurrentProject || boardsState.boards.isEmpty)) {
        Future.microtask(() => boardsNotifier.loadBoards(selectedProject.id));
      }
      
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        drawer: const AppSidebar(),
        appBar: AppBar(
          title: Text(
            selectedProject.name.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.2),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.blueGrey[900],
          actions: [
            if (boardsState.boards.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: boardsState.selectedBoardId,
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
                        final label = location.isEmpty ? b.name : '$location / ${b.name}';
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
              ),
            const NotificationBell(),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.video_call_outlined),
              tooltip: 'Звонок',
              onPressed: () async {
                final boardId = boardsState.selectedBoardId;
                if (boardId == null) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Выберите доску для звонка')),
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
                const PopupMenuItem<int>(
                  value: 3,
                  child: Text('Структура проекта'),
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
                  } else if (value == 3) {
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProjectStructureScreen(
                          projectId: selectedProject.id,
                          projectName: selectedProject.name,
                        ),
                      ),
                    );
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
        body: Column(
          children: [
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
                        kanbanState.demoMessage ?? 'Demo Mode: See project_members setup instructions in fix_rls.sql.',
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
              child: KanbanBoardWidget(
                projectId: selectedProject.id,
                boardId: boardsState.selectedBoardId,
              ),
            ),
          ],
        ),
      );
    });
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
