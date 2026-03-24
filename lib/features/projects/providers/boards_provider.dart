import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_client.dart';
import '../domain/entities/board.dart';

class BoardsState {
  const BoardsState({
    this.boards = const [],
    this.selectedBoardId,
    this.loadedProjectId,
    this.isLoading = false,
    this.error,
  });

  final List<ProjectBoard> boards;
  final String? selectedBoardId;
  final String? loadedProjectId;
  final bool isLoading;
  final String? error;

  BoardsState copyWith({
    List<ProjectBoard>? boards,
    String? selectedBoardId,
    String? loadedProjectId,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearSelectedBoard = false,
  }) {
    return BoardsState(
      boards: boards ?? this.boards,
      selectedBoardId: clearSelectedBoard ? null : (selectedBoardId ?? this.selectedBoardId),
      loadedProjectId: loadedProjectId ?? this.loadedProjectId,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class BoardsNotifier extends StateNotifier<BoardsState> {
  BoardsNotifier(this._supabase) : super(const BoardsState());

  final SupabaseClientService _supabase;

  Future<void> loadBoards(String projectId, {bool force = false}) async {
    if (!force && state.isLoading && state.loadedProjectId == projectId) {
      return;
    }
    if (!force &&
        !state.isLoading &&
        state.loadedProjectId == projectId &&
        state.error == null) {
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      loadedProjectId: projectId,
      clearSelectedBoard: true,
    );
    try {
      final rows = await _supabase.fetchList<Map<String, dynamic>>(
        tableName: 'project_boards',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
        orderBy: [const Ordering('created_at', ascending: true)],
      );
      final boards = rows.map(ProjectBoard.fromJson).toList();
      final userRole = await _getCurrentUserRole(projectId);
      final visibleBoards = await _filterVisibleBoards(
        projectId: projectId,
        boards: boards,
        userRole: userRole,
      );
      final selectedBoardId = _resolveSelectedBoardId(
        boards: visibleBoards,
        current: state.selectedBoardId,
      );
      state = state.copyWith(
        boards: visibleBoards,
        selectedBoardId: selectedBoardId,
        loadedProjectId: projectId,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        loadedProjectId: projectId,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<String?> ensureProjectCommunicationBoard(String projectId) async {
    if (state.loadedProjectId != projectId) {
      await loadBoards(projectId);
    }
    if (state.boards.isNotEmpty) {
      return state.boards.first.id;
    }

    try {
      final created = await _supabase.insert<Map<String, dynamic>>(
        tableName: 'boards',
        fromJson: (json) => json,
        data: {
          'project_id': projectId,
          'name': 'Общая коммуникация',
          'created_by': _supabase.currentUserId,
        },
      );

      await loadBoards(projectId, force: true);
      return created['id']?.toString() ??
          (state.boards.isNotEmpty ? state.boards.first.id : null);
    } catch (_) {
      return null;
    }
  }

  void selectBoard(String? boardId) {
    if (boardId == null) {
      state = state.copyWith(clearSelectedBoard: true);
      return;
    }
    state = state.copyWith(selectedBoardId: boardId);
  }

  String? _resolveSelectedBoardId({
    required List<ProjectBoard> boards,
    required String? current,
  }) {
    if (current != null && boards.any((b) => b.id == current)) {
      return current;
    }
    return null;
  }

  Future<String?> _getCurrentUserRole(String projectId) async {
    final userId = _supabase.currentUserId;
    if (userId == null) return null;
    final member = await _supabase.fetchSingle<Map<String, dynamic>>(
      tableName: 'project_members',
      fromJson: (json) => json,
      select: 'role',
      filters: [
        QueryFilter('project_id', 'eq', projectId),
        QueryFilter('user_id', 'eq', userId),
      ],
    );
    return member?['role'] as String?;
  }

  Future<List<ProjectBoard>> _filterVisibleBoards({
    required String projectId,
    required List<ProjectBoard> boards,
    required String? userRole,
  }) async {
    if (boards.isEmpty) return boards;
    if (userRole == 'owner' || userRole == 'admin') return boards;

    final userId = _supabase.currentUserId;
    if (userId == null) return [boards.first];

    final access = await _supabase.fetchSingle<Map<String, dynamic>>(
      tableName: 'project_member_access',
      fromJson: (json) => json,
      filters: [
        QueryFilter('project_id', 'eq', projectId),
        QueryFilter('user_id', 'eq', userId),
      ],
    );

    final allowedDepartmentIds = _toStringSet(access?['department_ids']);
    final allowedFolderIds = _toStringSet(access?['folder_ids']);

    final mainBoard = boards.first;
    final visible = boards.where((b) {
      if (b.id == mainBoard.id) return true;
      if (b.departmentId != null && allowedDepartmentIds.contains(b.departmentId)) {
        return true;
      }
      if (b.folderId != null && allowedFolderIds.contains(b.folderId)) {
        return true;
      }
      return false;
    }).toList();

    return visible.isEmpty ? [mainBoard] : visible;
  }

  Set<String> _toStringSet(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toSet();
    }
    return <String>{};
  }
}

final boardsProvider = StateNotifierProvider<BoardsNotifier, BoardsState>((ref) {
  return BoardsNotifier(SupabaseClientService.instance);
});

