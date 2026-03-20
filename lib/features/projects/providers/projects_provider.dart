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

      // If only one project exists, auto-select it
      if (projects.length == 1 && state.selectedProjectId == null) {
        selectProject(projects.first.id);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void selectProject(String? projectId) {
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
    try {
      // Find user by email
      final userData = await _supabaseService.fetchSingle<Map<String, dynamic>>(
        tableName: 'users',
        fromJson: (json) => json,
        filters: [QueryFilter('email', 'eq', email)],
      );

      if (userData == null) {
        throw const ServerException('User with this email not found');
      }

      await _supabaseService.insert<Map<String, dynamic>>(
        tableName: 'project_members',
        data: {
          'project_id': projectId,
          'user_id': userData['id'],
          'role': 'member',
        },
        fromJson: (json) => json,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
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
}

// Providers
final projectsProvider = StateNotifierProvider<ProjectsNotifier, ProjectsState>((ref) {
  final supabaseService = SupabaseClientService.instance;
  return ProjectsNotifier(supabaseService);
});

final selectedProjectProvider = Provider<Project?>((ref) {
  final state = ref.watch(projectsProvider);
  if (state.selectedProjectId == null) return null;
  return state.projects.firstWhere(
    (p) => p.id == state.selectedProjectId,
    orElse: () => state.projects.first, // Fallback if not found yet
  );
});
