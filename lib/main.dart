import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/services/supabase_client.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/presentation/widgets/auth_form.dart';
import 'features/kanban/presentation/widgets/kanban_board.dart';
import 'features/kanban/providers/kanban_provider.dart';
import 'shared/presentation/widgets/loading_screen.dart';

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
    final kanbanState = ref.watch(kanbanProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: _buildHome(initState, authState, kanbanState, ref),
    );
  }

  Widget _buildHome(
    SupabaseInitializationState initState,
    AppAuthState authState,
    KanbanState kanbanState,
    WidgetRef ref,
  ) {
    if (!initState.isInitialized) {
      return _InitializationErrorScreen(error: initState.error);
    }

    if (authState.isLoading) {
      return const LoadingScreen();
    }

    if (authState.user == null) {
      return const AuthForm();
    }

    return KanbanBoardWrapper(kanbanState: kanbanState);
  }
}

class KanbanBoardWrapper extends StatelessWidget {
  const KanbanBoardWrapper({super.key, required this.kanbanState});

  final KanbanState kanbanState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TaskFlow - Kanban Board'),
      ),
      body: Column(
        children: [
          if (kanbanState.isDemoData)
            Container(
              width: double.infinity,
              color: Colors.orange[50],
              padding: const EdgeInsets.all(12),
              child: Text(
                kanbanState.demoMessage ??
                    'Демо-режим: подключите Supabase проект и добавьте себя в project_members, чтобы увидеть реальные данные.',
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else if (kanbanState.error != null)
            Container(
              width: double.infinity,
              color: Colors.red[50],
              padding: const EdgeInsets.all(12),
              child: Text(
                kanbanState.error!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: KanbanBoardWidget(projectId: kanbanState.currentProjectId ?? 'demo-project'),
          ),
        ],
      ),
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
