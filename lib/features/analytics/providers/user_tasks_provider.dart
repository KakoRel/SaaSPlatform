import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saas_platform/features/kanban/domain/entities/task.dart';

import '../../../core/services/supabase_client.dart';

/// Tasks accessible to the current user across ALL projects.
///
/// Uses DB view `public.project_tasks`, which already filters by project membership.
final userTasksProvider = FutureProvider<List<Task>>((ref) async {
  final supabase = SupabaseClientService.instance;

  if (!supabase.isInitialized || supabase.currentUserId == null) {
    return const [];
  }

  return supabase.fetchList<Task>(
    tableName: 'project_tasks',
    select:
        'id,project_id,title,description,assignee_id,creator_id,status,priority,due_date,completed_at,position,image_url,created_at,updated_at,assignee_name,assignee_email,creator_name,creator_email',
    fromJson: (json) => Task.fromJson(json),
  );
});

Future<List<Task>> _fetchUserTasksForStream() async {
  final supabase = SupabaseClientService.instance;

  if (!supabase.isInitialized || supabase.currentUserId == null) {
    return const [];
  }

  return supabase.fetchList<Task>(
    tableName: 'project_tasks',
    select:
        'id,project_id,title,description,assignee_id,creator_id,status,priority,due_date,completed_at,position,image_url,created_at,updated_at,assignee_name,assignee_email,creator_name,creator_email',
    fromJson: (json) => Task.fromJson(json),
  );
}

/// Stream of tasks accessible to the current user across ALL projects.
///
/// It uses realtime events on `public.tasks` and refetches from the
/// `public.project_tasks` view on every change, so UI updates immediately
/// without requiring a page refresh.
final userTasksStreamProvider = StreamProvider<List<Task>>((ref) {
  final controller = StreamController<List<Task>>();
  RealtimeChannel? channel;

  Future<void> emitNow() async {
    try {
      controller.add(await _fetchUserTasksForStream());
    } catch (e, st) {
      controller.addError(e, st);
    }
  }

  // Emit first value.
  emitNow();

  final supabase = SupabaseClientService.instance;
  final userId = supabase.currentUserId;
  if (supabase.isInitialized && userId != null) {
    channel = supabase.subscribeToTable(
      tableName: 'tasks',
      channelId: 'user_tasks_$userId',
      callback: (_) {
        // Refetch on every postgres change so the view stays consistent.
        emitNow();
      },
    );
    channel.subscribe();
  }

  ref.onDispose(() async {
    try {
      await channel?.unsubscribe();
    } catch (_) {
      // ignore
    }
    await controller.close();
  });

  return controller.stream;
});

