import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/projects_provider.dart';
import '../../domain/entities/project.dart';

class ProjectSelectionScreen extends ConsumerStatefulWidget {
  const ProjectSelectionScreen({super.key});

  @override
  ConsumerState<ProjectSelectionScreen> createState() => _ProjectSelectionScreenState();
}

class _ProjectSelectionScreenState extends ConsumerState<ProjectSelectionScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(projectsProvider.notifier).loadProjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E24),
      appBar: AppBar(
        title: const Text(
          'Проекты',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1E1E24),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 28),
            tooltip: 'Создать Проект',
            onPressed: () => _showCreateProjectDialog(context, ref),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : state.error != null
                ? Center(child: Text('Ошибка: ${state.error}', style: const TextStyle(color: Colors.white)))
                : state.projects.isEmpty
                    ? _buildEmptyState(context, ref)
                    : _buildProjectGrid(context, ref, state.projects),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rocket_launch_outlined, size: 80, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(height: 12),
          const Text(
            'Добро пожаловать!',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Создайте свой первый проект, чтобы начать работу.',
            style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _showCreateProjectDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Создать новый проект'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              backgroundColor: const Color(0xFF4C9AFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectGrid(BuildContext context, WidgetRef ref, List<Project> projects) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 1 : 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: isMobile ? 2.5 : 1.8,
      ),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        return _ProjectGridItem(project: project);
      },
    );
  }

  Future<void> _showCreateProjectDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    // Capture notifier before async gaps or potential disposal
    final projectsNotifier = ref.read(projectsProvider.notifier);

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF252830),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF343945)),
        ),
        title: const Text('Новый проект', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
            child: const Text('Отмена', style: TextStyle(color: Color(0xFFB6C2CF))),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                // Use captured notifier
                projectsNotifier.createProject(
                      nameController.text.trim(),
                      descController.text.trim().isEmpty ? null : descController.text.trim(),
                    );
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4C9AFF),
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

class _ProjectGridItem extends ConsumerWidget {
  const _ProjectGridItem({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252830),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF343945), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => ref.read(projectsProvider.notifier).selectProject(project.id),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B2D31),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder_copy, color: Color(0xFF4C9AFF), size: 24),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios, color: Color(0xFFB6C2CF), size: 16),
                ],
              ),
              const Spacer(),
              Text(
                project.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                project.description ?? 'Описание отсутствует',
                style: TextStyle(
                  color: const Color(0xFFB6C2CF),
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
