import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/projects/providers/projects_provider.dart';
import '../../../features/projects/presentation/widgets/project_members_dialog.dart';

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsState = ref.watch(projectsProvider);
    final projectsNotifier = ref.read(projectsProvider.notifier);
    final selectedProject = ref.watch(selectedProjectProvider);

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.dashboard, color: Colors.white, size: 48),
                  SizedBox(height: 8),
                  Text(
                    'TaskFlow',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const ListTile(
                  title: Text(
                    'PROJECTS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),
                ...projectsState.projects.map((project) {
                  final isSelected = project.id == selectedProject?.id;
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: isSelected ? Theme.of(context).primaryColor : Colors.grey[300],
                      child: Text(
                        project.name[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    title: Text(
                      project.name,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Theme.of(context).primaryColor : null,
                      ),
                    ),
                    onTap: () {
                      projectsNotifier.selectProject(project.id);
                      Navigator.pop(context); // Close drawer
                    },
                    selected: isSelected,
                  );
                }),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add New Project'),
                  onTap: () {
                    Navigator.pop(context);
                    _showCreateProjectDialog(context, ref);
                  },
                ),
                if (selectedProject != null) ...[
                  const Divider(),
                  const ListTile(
                    title: Text(
                      'SETTINGS',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: const Text('Project Members'),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              // App settings
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () {
              // Sign out logic
              // ref.read(authNotifierProvider.notifier).signOut();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _showCreateProjectDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Project Name'),
              autofocus: true,
            ),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'Description (Optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                ref.read(projectsProvider.notifier).createProject(
                      nameController.text.trim(),
                      descController.text.trim().isEmpty ? null : descController.text.trim(),
                    );
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
