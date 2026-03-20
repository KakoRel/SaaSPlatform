import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saas_platform/features/auth/providers/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameController;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final user = ref.read(authNotifierProvider).user;
    _nameController = TextEditingController(text: user?.fullName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );

    if (image == null) return;

    try {
      final bytes = await image.readAsBytes();
      final ext = image.path.split('.').last;
      await ref.read(authNotifierProvider.notifier).uploadAvatar(bytes, ext);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Аватар обновлён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось обновить аватар: $e')),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    await ref.read(authNotifierProvider.notifier).updateProfile(
      fullName: _nameController.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль обновлен')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.user;
    final avatarUrl = user?.avatarUrl;
    final initials = (user?.fullName ?? user?.email ?? '?')[0].toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      body: authState.isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Avatar Section
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.blue[50],
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                avatarUrl,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Text(
                                  initials,
                                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                                ),
                              ),
                            )
                          : Text(
                              initials,
                              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                            ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickAvatar,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue[600],
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Profile Section
              Text(
                'Ваш Профиль',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Полное имя',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                enabled: false,
                controller: TextEditingController(text: user?.email),
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Сохранить изменения'),
              ),

              const SizedBox(height: 40),

              // Account Status Section
              Text(
                'Статус Аккаунта',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (user?.isEmailConfirmed ?? false) ? Colors.green[50] : Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (user?.isEmailConfirmed ?? false) ? Colors.green[200]! : Colors.orange[200]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      (user?.isEmailConfirmed ?? false) ? Icons.check_circle : Icons.warning_amber_rounded,
                      color: (user?.isEmailConfirmed ?? false) ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (user?.isEmailConfirmed ?? false) 
                                ? 'Email подтвержден' 
                                : 'Email не подтвержден',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (!(user?.isEmailConfirmed ?? false))
                            const Text(
                              'Подтвердите email, чтобы получить полный доступ к функциям.',
                              style: TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    if (!(user?.isEmailConfirmed ?? false))
                      TextButton(
                        onPressed: () => ref.read(authNotifierProvider.notifier).resendConfirmationEmail(),
                        child: const Text('Отправить еще раз'),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              // App Info
              const Center(
                child: Text(
                  'Версия 1.0.0',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
    );
  }
}
