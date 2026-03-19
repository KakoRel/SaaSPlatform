import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_client.dart';
import '../../features/kanban/domain/entities/task.dart';

enum Permission {
  view,
  create,
  update,
  delete,
  invite,
  manage,
}

enum ProjectRole {
  owner,
  admin,
  member,
  viewer;

  static ProjectRole fromString(String value) {
    return ProjectRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => ProjectRole.viewer,
    );
  }
}

class RLSUtils {
  RLSUtils._();

  static Future<ProjectRole?> getUserProjectRole(String projectId) async {
    try {
      final memberData = await SupabaseClientService.instance.fetchSingle<Map<String, dynamic>>(
        tableName: 'project_members',
        fromJson: (json) => json,
        filters: [
          QueryFilter('project_id', 'eq', projectId),
          QueryFilter('user_id', 'eq', SupabaseClientService.instance.currentUserId!),
        ],
      );

      if (memberData == null) return null;

      return ProjectRole.fromString(memberData['role'] as String? ?? 'viewer');
    } catch (e) {
      return null;
    }
  }

  static bool hasPermission(ProjectRole role, Permission permission) {
    switch (permission) {
      case Permission.view:
        return true;
      case Permission.create:
      case Permission.update:
        return role == ProjectRole.owner ||
               role == ProjectRole.admin ||
               role == ProjectRole.member;
      case Permission.delete:
      case Permission.invite:
      case Permission.manage:
        return role == ProjectRole.owner ||
               role == ProjectRole.admin;
    }
  }

  static bool canEditTask(Task task, ProjectRole userRole) {
    final currentUserId = SupabaseClientService.instance.currentUserId;
    if (task.creatorId == currentUserId) return true;
    if (task.assigneeId == currentUserId) return true;
    return hasPermission(userRole, Permission.update);
  }

  static bool canDeleteTask(Task task, ProjectRole userRole) {
    final currentUserId = SupabaseClientService.instance.currentUserId;
    if (task.creatorId == currentUserId) return true;
    return hasPermission(userRole, Permission.delete);
  }

  static bool canInviteMembers(ProjectRole userRole) {
    return hasPermission(userRole, Permission.invite);
  }

  static bool canManageProject(ProjectRole userRole) {
    return hasPermission(userRole, Permission.manage);
  }
}

// Permission providers for UI
final projectRoleProvider = FutureProvider.family<ProjectRole?, String>((ref, projectId) async {
  return RLSUtils.getUserProjectRole(projectId);
});

final canCreateTaskProvider = Provider.family<bool, String>((ref, projectId) {
  final roleAsync = ref.watch(projectRoleProvider(projectId));
  return roleAsync.when(
    data: (role) => role != null ? RLSUtils.hasPermission(role, Permission.create) : false,
    loading: () => false,
    error: (_, _) => false,
  );
});

final canInviteMembersProvider = Provider.family<bool, String>((ref, projectId) {
  final roleAsync = ref.watch(projectRoleProvider(projectId));
  return roleAsync.when(
    data: (role) => role != null ? RLSUtils.canInviteMembers(role) : false,
    loading: () => false,
    error: (_, _) => false,
  );
});

final canManageProjectProvider = Provider.family<bool, String>((ref, projectId) {
  final roleAsync = ref.watch(projectRoleProvider(projectId));
  return roleAsync.when(
    data: (role) => role != null ? RLSUtils.canManageProject(role) : false,
    loading: () => false,
    error: (_, _) => false,
  );
});

// Permission widget helper
class PermissionGuard extends ConsumerWidget {
  const PermissionGuard({
    super.key,
    required this.projectId,
    required this.permission,
    required this.child,
    this.fallback,
  });

  final String projectId;
  final Permission permission;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(projectRoleProvider(projectId));

    return roleAsync.when(
      data: (role) {
        if (role != null && RLSUtils.hasPermission(role, permission)) {
          return child;
        }
        return fallback ?? const SizedBox.shrink();
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => fallback ?? const SizedBox.shrink(),
    );
  }
}
