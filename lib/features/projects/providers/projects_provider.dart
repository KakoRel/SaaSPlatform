import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_client.dart';
import '../domain/entities/project.dart';
import '../../../core/errors/exceptions.dart';

class ProjectsState {
  const ProjectsState({
    this.projects = const [],
    this.isLoading = false,
    this.error,
    this.selectedProjectId,
  });

  final List<Project> projects;
  final bool isLoading;
  final String? error;
  final String? selectedProjectId;

  ProjectsState copyWith({
    List<Project>? projects,
    bool? isLoading,
    String? error,
    String? selectedProjectId,
    bool clearError = false,
    bool clearSelectedProject = false,
  }) {
    return ProjectsState(
      projects: projects ?? this.projects,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      selectedProjectId: clearSelectedProject ? null : (selectedProjectId ?? this.selectedProjectId),
    );
  }
}

class ProjectsNotifier extends StateNotifier<ProjectsState> {
  ProjectsNotifier(this._supabaseService) : super(const ProjectsState());

  final SupabaseClientService _supabaseService;

  Future<void> loadProjects() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final projectsData = await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'user_projects',
        fromJson: (json) => json,
        orderBy: [const Ordering('created_at', ascending: false)],
      );

      final projects = projectsData.map((data) => Project.fromJson(data)).toList();
      state = state.copyWith(projects: projects, isLoading: false);

    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void selectProject(String? projectId) {
    if (projectId == null) {
      state = state.copyWith(clearSelectedProject: true);
      return;
    }
    state = state.copyWith(selectedProjectId: projectId);
  }

  Future<Project?> createProject(String name, String? description) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final userId = _supabaseService.currentUserId;
      if (userId == null) throw const AuthenticationException('User not authenticated');

      final newProject = await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'projects',
        data: {
          'name': name,
          'description': description,
          'owner_id': userId,
        },
        fromJson: (json) => json,
      );

      final project = Project.fromJson(newProject);
      state = state.copyWith(
        projects: [project, ...state.projects],
        isLoading: false,
        selectedProjectId: project.id,
      );
      return project;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  Future<void> inviteMember(String projectId, String email) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final searchEmail = email.trim().toLowerCase();

    try {
      // Public.users is protected by RLS (по умолчанию можно читать только свой профиль),
      // поэтому для invite делаем lookup через SECURITY DEFINER функцию.
      final rpcResult = await _supabaseService.rpc(
        functionName: 'find_user_id_by_email_for_project',
        params: {
          'p_project_id': projectId,
          'p_email': searchEmail,
        },
      );

      final userId = rpcResult?.toString();
      if (userId == null || userId.isEmpty) {
        throw ServerException('Пользователь с email "$email" не найден в системе. '
            'Убедитесь, что он уже зарегистрирован.');
      }

      // Check if already a member
      final existingMember = await _supabaseService.fetchSingle<Map<String, dynamic>>(
        tableName: 'project_members',
        fromJson: (json) => json,
        filters: [
          QueryFilter('project_id', 'eq', projectId),
          QueryFilter('user_id', 'eq', userId),
        ],
      );

      if (existingMember != null) {
        throw const ServerException('Этот пользователь уже является участником проекта');
      }

      await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'project_members',
        data: {
          'project_id': projectId,
          'user_id': userId,
          'role': 'member',
        },
        fromJson: (json) => json,
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e is ServerException ? e.message : e.toString(),
      );
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getProjectMembers(String projectId) async {
    try {
      final members = await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'project_members',
        select: '*, users(full_name, email, avatar_url)',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
      );
      return members;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getProjectDepartments(String projectId) async {
    try {
      return await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'departments',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
        orderBy: [const Ordering('name', ascending: true)],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getProjectFolders(String projectId) async {
    try {
      return await _supabaseService.fetchList<Map<String, dynamic>>(
        tableName: 'project_folders',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
        orderBy: [const Ordering('name', ascending: true)],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<Map<String, dynamic>?> getMemberAccess({
    required String projectId,
    required String userId,
  }) async {
    try {
      return await _supabaseService.fetchSingle<Map<String, dynamic>>(
        tableName: 'project_member_access',
        fromJson: (json) => json,
        filters: [
          QueryFilter('project_id', 'eq', projectId),
          QueryFilter('user_id', 'eq', userId),
        ],
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  Future<void> saveMemberAccess({
    required String projectId,
    required String userId,
    required List<String> departmentIds,
    required List<String> folderIds,
  }) async {
    try {
      final existing = await getMemberAccess(projectId: projectId, userId: userId);
      if (existing == null) {
        await _supabaseService.insert<Map<String, dynamic>>(
          tableName: 'project_member_access',
          data: {
            'project_id': projectId,
            'user_id': userId,
            'department_ids': departmentIds,
            'folder_ids': folderIds,
          },
          fromJson: (json) => json,
        );
      } else {
        await _supabaseService.updateWhere<Map<String, dynamic>>(
          tableName: 'project_member_access',
          data: {
            'department_ids': departmentIds,
            'folder_ids': folderIds,
          },
          fromJson: (json) => json,
          filters: [
            QueryFilter('project_id', 'eq', projectId),
            QueryFilter('user_id', 'eq', userId),
          ],
        );
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> leaveProject(String projectId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final currentUserId = _supabaseService.currentUserId;
    if (currentUserId == null) {
      throw const AuthenticationException('User not authenticated');
    }

    try {
      await _supabaseService.deleteWhere(
        tableName: 'project_members',
        filters: [
          QueryFilter('project_id', 'eq', projectId),
          QueryFilter('user_id', 'eq', currentUserId),
        ],
      );

      await loadProjects();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e is ServerException ? e.message : e.toString(),
      );
      rethrow;
    }
  }

  Future<void> deleteProject(String projectId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _supabaseService.delete(
        tableName: 'projects',
        id: projectId,
      );
      await loadProjects();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e is ServerException ? e.message : e.toString(),
      );
      rethrow;
    }
  }
}

// Providers
final projectsProvider = StateNotifierProvider<ProjectsNotifier, ProjectsState>((ref) {
  final supabaseService = SupabaseClientService.instance;
  return ProjectsNotifier(supabaseService);
});

final selectedProjectProvider = Provider<Project?>((ref) {
  final state = ref.watch(projectsProvider);
  if (state.projects.isEmpty) return null;
  if (state.selectedProjectId == null) return null;
  return state.projects.firstWhere(
    (p) => p.id == state.selectedProjectId,
    orElse: () => state.projects.first, // Fallback if not found yet
  );
});
