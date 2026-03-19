import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_client.dart';
import '../../features/auth/providers/auth_provider.dart';

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
  viewer,
}

class RLSUtils {
  RLSUtils._();

  static Future<ProjectRole?> getUserProjectRole(String projectId) async {
    try {
      final memberData = await SupabaseClientService.instance.fetchSingle<Map<String, dynamic>>(
        tableName: 'project_members',
        fromJson: (json) => json,
        filters: [
          Filter('project_id', 'eq', projectId),
          Filter('user_id', 'eq', SupabaseClientService.instance.currentUserId!),
        ],
      );

      if (memberData == null) return null;
      
      return ProjectRole.values.firstWhere(
        (role) => role.name == memberData['role'],
        orElse: () => ProjectRole.viewer,
      );
    } catch (e) {
      return null;
    }
  }

  static bool hasPermission(ProjectRole role, Permission permission) {
    switch (permission) {
      case Permission.view:
        return true; // All members can view
      
      case Permission.create:
        return role == ProjectRole.owner || 
               role == ProjectRole.admin || 
               role == ProjectRole.member;
      
      case Permission.update:
        return role == ProjectRole.owner || 
               role == ProjectRole.admin || 
               role == ProjectRole.member;
      
      case Permission.delete:
        return role == ProjectRole.owner || 
               role == ProjectRole.admin;
      
      case Permission.invite:
        return role == ProjectRole.owner || 
               role == ProjectRole.admin;
      
      case Permission.manage:
        return role == ProjectRole.owner || 
               role == ProjectRole.admin;
    }
  }

  static bool canEditTask(Task task, ProjectRole userRole) {
    // Task creator can always edit
    if (task.creatorId == SupabaseClientService.instance.currentUserId) {
      return true;
    }
    
    // Task assignee can edit (limited fields)
    if (task.assigneeId == SupabaseClientService.instance.currentUserId) {
      return true;
    }
    
    // Project members with sufficient role can edit
    return hasPermission(userRole, Permission.update);
  }

  static bool canDeleteTask(Task task, ProjectRole userRole) {
    // Task creator can delete
    if (task.creatorId == SupabaseClientService.instance.currentUserId) {
      return true;
    }
    
    // Project admins and owners can delete
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
  return await RLSUtils.getUserProjectRole(projectId);
});

final canViewProjectProvider = Provider.family<bool, String>((ref, projectId) {
  final roleAsync = ref.watch(projectRoleProvider(projectId));
  return roleAsync.when(
    data: (role) => role != null,
    loading: () => false,
    error: (_, __) => false,
  );
});

final canCreateTaskProvider = Provider.family<bool, String>((ref, projectId) {
  final roleAsync = ref.watch(projectRoleProvider(projectId));
  return roleAsync.when(
    data: (role) => role != null ? RLSUtils.hasPermission(role, Permission.create) : false,
    loading: () => false,
    error: (_, __) => false,
  );
});

final canInviteMembersProvider = Provider.family<bool, String>((ref, projectId) {
  final roleAsync = ref.watch(projectRoleProvider(projectId));
  return roleAsync.when(
    data: (role) => role != null ? RLSUtils.canInviteMembers(role) : false,
    loading: () => false,
    error: (_, __) => false,
  );
});

final canManageProjectProvider = Provider.family<bool, String>((ref, projectId) {
  final roleAsync = ref.watch(projectRoleProvider(projectId));
  return roleAsync.when(
    data: (role) => role != null ? RLSUtils.canManageProject(role) : false,
    loading: () => false,
    error: (_, __) => false,
  );
});

// Task-specific permission providers
final taskPermissionProvider = Provider.family<bool, Task>((ref, task) {
  final roleAsync = ref.watch(projectRoleProvider(task.projectId));
  return roleAsync.when(
    data: (role) => role != null ? RLSUtils.canEditTask(task, role) : false,
    loading: () => false,
    error: (_, __) => false,
  );
});

final canDeleteTaskProvider = Provider.family<bool, Task>((ref, task) {
  final roleAsync = ref.watch(projectRoleProvider(task.projectId));
  return roleAsync.when(
    data: (role) => role != null ? RLSUtils.canDeleteTask(task, role) : false,
    loading: () => false,
    error: (_, __) => false,
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
      error: (_, __) => fallback ?? const SizedBox.shrink(),
    );
  }
}

// Task permission widget helper
class TaskPermissionGuard extends ConsumerWidget {
  const TaskPermissionGuard({
    super.key,
    required this.task,
    required this.canEdit,
    required this.child,
    this.fallback,
  });

  final Task task;
  final bool canEdit;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPermission = ref.watch(taskPermissionProvider(task));

    if (canEdit && hasPermission) {
      return child;
    }
    return fallback ?? const SizedBox.shrink();
  }
}

// RLS check utility functions for common operations
class RLSChecks {
  RLSChecks._();

  static Future<bool> canAccessProject(String projectId) async {
    final role = await RLSUtils.getUserProjectRole(projectId);
    return role != null;
  }

  static Future<bool> canCreateTaskInProject(String projectId) async {
    final role = await RLSUtils.getUserProjectRole(projectId);
    return role != null && RLSUtils.hasPermission(role, Permission.create);
  }

  static Future<bool> canInviteToProject(String projectId) async {
    final role = await RLSUtils.getUserProjectRole(projectId);
    return role != null && RLSUtils.canInviteMembers(role);
  }

  static Future<bool> canManageProjectSettings(String projectId) async {
    final role = await RLSUtils.getUserProjectRole(projectId);
    return role != null && RLSUtils.canManageProject(role);
  }

  static Future<bool> canEditTask(Task task) async {
    final role = await RLSUtils.getUserProjectRole(task.projectId);
    return role != null && RLSUtils.canEditTask(task, role);
  }

  static Future<bool> canDeleteTask(Task task) async {
    final role = await RLSUtils.getUserProjectRole(task.projectId);
    return role != null && RLSUtils.canDeleteTask(task, role);
  }

  // Quick RLS check for UI (synchronous, uses cached role)
  static bool canEditTaskSync(Task task, ProjectRole? userRole) {
    if (userRole == null) return false;
    return RLSUtils.canEditTask(task, userRole);
  }

  static bool canDeleteTaskSync(Task task, ProjectRole? userRole) {
    if (userRole == null) return false;
    return RLSUtils.canDeleteTask(task, userRole);
  }

  static bool canCreateTaskSync(ProjectRole? userRole) {
    if (userRole == null) return false;
    return RLSUtils.hasPermission(userRole, Permission.create);
  }

  static bool canInviteMembersSync(ProjectRole? userRole) {
    if (userRole == null) return false;
    return RLSUtils.canInviteMembers(userRole);
  }

  static bool canManageProjectSync(ProjectRole? userRole) {
    if (userRole == null) return false;
    return RLSUtils.canManageProject(userRole);
  }
}
