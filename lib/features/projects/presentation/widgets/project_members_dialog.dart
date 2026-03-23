import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/projects_provider.dart';
import '../../../../core/services/supabase_client.dart';

class ProjectMembersDialog extends ConsumerStatefulWidget {
  const ProjectMembersDialog({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectMembersDialog> createState() => _ProjectMembersDialogState();
}

class _ProjectMembersDialogState extends ConsumerState<ProjectMembersDialog> {
  final _emailController = TextEditingController();
  bool _isInviting = false;
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(projectsProvider.notifier);

    return AlertDialog(
      title: const Text('Участники Проекта'),
      content: SizedBox(
        width: 760,
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
                      labelText: 'Пригласить по почте',
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
                key: ValueKey(_refreshKey),
                future: notifier.getProjectMembers(widget.projectId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text('Ошибка: ${snapshot.error}');
                  }
                  final members = snapshot.data ?? [];
                  final currentUserId = SupabaseClientService.instance.currentUserId;
                  Map<String, dynamic>? currentMember;
                  for (final m in members) {
                    if (m['user_id']?.toString() == currentUserId) {
                      currentMember = m;
                      break;
                    }
                  }
                  final currentRole = currentMember?['role']?.toString();
                  final canManageRights = currentRole == 'owner' || currentRole == 'admin';

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];
                      // Supabase nested select key can differ depending on relationship naming.
                      final dynamic userDataRaw = member['users'] ?? member['user'];
                      final userData = userDataRaw is Map<String, dynamic> ? userDataRaw : null;
                      final email = userData?['email'] as String? ?? member['email'] as String? ?? 'Unknown';
                      final name = userData?['full_name'] as String? ?? member['full_name'] as String? ?? email;
                      final role = member['role'] as String? ?? 'member';
                      final memberUserId = member['user_id']?.toString() ?? '';

                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(name[0].toUpperCase()),
                        ),
                        title: Text(name),
                        subtitle: Text(email),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canManageRights && role == 'member')
                              OutlinedButton(
                                onPressed: () => _openRightsDialog(memberUserId, name),
                                child: const Text('Права'),
                              ),
                            const SizedBox(width: 8),
                            Container(
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
                          ],
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
          child: const Text('Закрыть'),
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
          const SnackBar(content: Text('Участник успешно приглашен')),
        );
        setState(() => _refreshKey++); // Refresh list
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

  Future<void> _openRightsDialog(String memberUserId, String memberName) async {
    final notifier = ref.read(projectsProvider.notifier);
    final departments = await notifier.getProjectDepartments(widget.projectId);
    final folders = await notifier.getProjectFolders(widget.projectId);
    final access = await notifier.getMemberAccess(
      projectId: widget.projectId,
      userId: memberUserId,
    );

    final selectedDepartments = <String>{
      ...((access?['department_ids'] as List?)?.map((e) => e.toString()) ?? const []),
    };
    final selectedFolders = <String>{
      ...((access?['folder_ids'] as List?)?.map((e) => e.toString()) ?? const []),
    };

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680, maxHeight: 640),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Права для $memberName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 6),
                    const Text('По умолчанию всегда доступна только Основная доска.'),
                    const SizedBox(height: 14),
                    const Text('Отделы', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          ...departments.map((d) {
                            final id = d['id']?.toString() ?? '';
                            return CheckboxListTile(
                              value: selectedDepartments.contains(id),
                              title: Text(d['name']?.toString() ?? ''),
                              onChanged: (value) {
                                setLocalState(() {
                                  if (value == true) {
                                    selectedDepartments.add(id);
                                  } else {
                                    selectedDepartments.remove(id);
                                  }
                                });
                              },
                            );
                          }),
                          const Divider(height: 20),
                          const Text('Папки', style: TextStyle(fontWeight: FontWeight.w600)),
                          ...folders.map((f) {
                            final id = f['id']?.toString() ?? '';
                            return CheckboxListTile(
                              value: selectedFolders.contains(id),
                              title: Text(f['name']?.toString() ?? ''),
                              onChanged: (value) {
                                setLocalState(() {
                                  if (value == true) {
                                    selectedFolders.add(id);
                                  } else {
                                    selectedFolders.remove(id);
                                  }
                                });
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Отмена'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            await notifier.saveMemberAccess(
                              projectId: widget.projectId,
                              userId: memberUserId,
                              departmentIds: selectedDepartments.toList(),
                              folderIds: selectedFolders.toList(),
                            );
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('Права сохранены')),
                            );
                            setState(() => _refreshKey++);
                          },
                          child: const Text('Сохранить'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
