import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/projects/providers/projects_provider.dart';
import '../../../features/projects/presentation/widgets/project_members_dialog.dart';
import 'package:saas_platform/features/auth/providers/auth_provider.dart';
import 'package:saas_platform/features/settings/presentation/pages/settings_screen.dart';
import 'package:saas_platform/features/analytics/presentation/pages/analytics_screen.dart';

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsState = ref.watch(projectsProvider);
    final projectsNotifier = ref.read(projectsProvider.notifier);
    final selectedProject = ref.watch(selectedProjectProvider);

    return Drawer(
      backgroundColor: Colors.blueGrey[900]?.withValues(alpha: 0.95),
      child: Column(
        children: [
          _buildSidebarHeader(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                const SizedBox(height: 20),
                _buildSectionHeader('ПРОЕКТЫ'),
                ...projectsState.projects.map((project) {
                  final isSelected = project.id == selectedProject?.id;
                  return _buildProjectItem(context, project, isSelected, projectsNotifier);
                }),
                const SizedBox(height: 8),
                _buildActionItem(
                  context,
                  icon: Icons.add_rounded,
                  label: 'Новый Проект',
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateProjectDialog(context, ref);
                  },
                ),
                if (selectedProject != null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(color: Colors.white10),
                  ),
                  _buildSectionHeader('НАСТРОЙКИ'),
                  _buildActionItem(
                    context,
                    icon: Icons.people_outline_rounded,
                    label: 'Участники Проекта',
                    onTap: () {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (context) => ProjectMembersDialog(projectId: selectedProject.id),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          _buildFooter(context, ref),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 20, bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[800]!, Colors.purple[800]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 40),
            SizedBox(height: 12),
            Text(
              'TaskFlow',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Colors.white38,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildProjectItem(
    BuildContext context,
    dynamic project,
    bool isSelected,
    ProjectsNotifier projectsNotifier,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () {
          projectsNotifier.selectProject(project.id);
          Navigator.pop(context);
        },
        dense: true,
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[400] : Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              project.name[0].toUpperCase(),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        title: Text(
          project.name,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        trailing: isSelected 
            ? const Icon(Icons.check_circle_rounded, color: Colors.blue, size: 16)
            : null,
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white70,
  }) {
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        label,
        style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildFooter(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildActionItem(
            context,
            icon: Icons.analytics_outlined,
            label: 'Аналитика',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsScreen()));
            },
          ),
          _buildActionItem(
            context,
            icon: Icons.settings_outlined,
            label: 'Настройки',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
          _buildActionItem(
            context,
            icon: Icons.logout_rounded,
            label: 'Выйти',
            color: Colors.redAccent[100]!,
            onTap: () {
              Navigator.pop(context); // Close drawer
              ref.read(authNotifierProvider.notifier).signOut();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateProjectDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final projectsNotifier = ref.read(projectsProvider.notifier);

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Новый Проект', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Название проекта',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: InputDecoration(
                labelText: 'Описание (необязательно)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена', style: TextStyle(color: Colors.grey[700])),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                projectsNotifier.createProject(
                      nameController.text.trim(),
                      descController.text.trim().isEmpty ? null : descController.text.trim(),
                    );
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }
}
