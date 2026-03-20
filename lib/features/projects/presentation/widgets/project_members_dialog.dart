import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/projects_provider.dart';

class ProjectMembersDialog extends ConsumerStatefulWidget {
  const ProjectMembersDialog({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectMembersDialog> createState() => _ProjectMembersDialogState();
}

class _ProjectMembersDialogState extends ConsumerState<ProjectMembersDialog> {
  final _emailController = TextEditingController();
  bool _isInviting = false;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(projectsProvider.notifier);

    return AlertDialog(
      title: const Text('Project Members'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Invite Section
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Invite by email',
                      hintText: 'user@example.com',
                    ),
                  ),
                ),
                IconButton(
                  icon: _isInviting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add),
                  onPressed: _isInviting ? null : _inviteMember,
                ),
              ],
            ),
            const Divider(height: 32),
            // Members List
            Flexible(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: notifier.getProjectMembers(widget.projectId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  }
                  final members = snapshot.data ?? [];
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      final userData = member['users'] as Map<String, dynamic>?;
                      final email = userData?['email'] as String? ?? 'Unknown';
                      final name = userData?['full_name'] as String? ?? email;
                      final role = member['role'] as String? ?? 'member';

                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(name[0].toUpperCase()),
                        ),
                        title: Text(name),
                        subtitle: Text(email),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withAlpha(50),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            role,
                            style: const TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _inviteMember() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isInviting = true);
    try {
      await ref.read(projectsProvider.notifier).inviteMember(widget.projectId, email);
      _emailController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member invited successfully')),
        );
        setState(() {}); // Refresh list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isInviting = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
