import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/services/supabase_client.dart';
import 'features/kanban/presentation/widgets/kanban_board.dart';
import 'features/auth/providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Supabase client service
    await SupabaseClientService.instance.initialize();
    runApp(const ProviderScope(child: MyApp()));
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Failed to initialize application',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Error: $e',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Please check your Supabase credentials and redeploy',
                  style: TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: authState.isLoading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : authState.user == null
              ? const LoginPage()
              : const KanbanBoardWidget(projectId: 'demo-project'),
    );
  }
}

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TaskFlow - Login'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.dashboard,
                size: 100,
                color: Colors.blue,
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to TaskFlow',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your SaaS Task Management Platform',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await ref.read(authNotifierProvider.notifier).signInWithEmail(
                      email: 'demo@taskflow.com',
                      password: 'password123',
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: const Text('Demo Login'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Use demo@taskflow.com / password123',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
