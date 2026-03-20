import 'package:flutter_riverpod/flutter_riverpod.dart';
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

