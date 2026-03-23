import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_client.dart';
import '../domain/entities/board.dart';

class BoardsState {
  const BoardsState({
    this.boards = const [],
    this.selectedBoardId,
    this.isLoading = false,
    this.error,
  });

  final List<ProjectBoard> boards;
  final String? selectedBoardId;
  final bool isLoading;
  final String? error;

  BoardsState copyWith({
    List<ProjectBoard>? boards,
    String? selectedBoardId,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return BoardsState(
      boards: boards ?? this.boards,
      selectedBoardId: selectedBoardId ?? this.selectedBoardId,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class BoardsNotifier extends StateNotifier<BoardsState> {
  BoardsNotifier(this._supabase) : super(const BoardsState());

  final SupabaseClientService _supabase;

  Future<void> loadBoards(String projectId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final rows = await _supabase.fetchList<Map<String, dynamic>>(
        tableName: 'project_boards',
        fromJson: (json) => json,
        filters: [QueryFilter('project_id', 'eq', projectId)],
        orderBy: [const Ordering('created_at', ascending: true)],
      );
      final boards = rows.map(ProjectBoard.fromJson).toList();
      final selectedBoardId = _resolveSelectedBoardId(
        boards: boards,
        current: state.selectedBoardId,
      );
      state = state.copyWith(
        boards: boards,
        selectedBoardId: selectedBoardId,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void selectBoard(String? boardId) {
    state = state.copyWith(selectedBoardId: boardId);
  }

  String? _resolveSelectedBoardId({
    required List<ProjectBoard> boards,
    required String? current,
  }) {
    if (current != null && boards.any((b) => b.id == current)) {
      return current;
    }
    if (boards.isEmpty) return null;
    return boards.first.id;
  }
}

final boardsProvider = StateNotifierProvider<BoardsNotifier, BoardsState>((ref) {
  return BoardsNotifier(SupabaseClientService.instance);
});

