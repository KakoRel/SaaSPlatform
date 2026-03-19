import 'package:freezed_annotation/freezed_annotation.dart';

part 'task.freezed.dart';
part 'task.g.dart';

enum TaskPriority {
  @JsonValue('low')
  low,
  @JsonValue('medium')
  medium,
  @JsonValue('high')
  high,
  @JsonValue('urgent')
  urgent,
}

enum TaskStatus {
  @JsonValue('todo')
  todo,
  @JsonValue('in_progress')
  inProgress,
  @JsonValue('review')
  review,
  @JsonValue('done')
  done,
}

@freezed
class Task with _$Task {
  const factory Task({
    required String id,
    required String projectId,
    required String title,
    String? description,
    String? assigneeId,
    required String creatorId,
    @Default(TaskStatus.todo) TaskStatus status,
    @Default(TaskPriority.medium) TaskPriority priority,
    DateTime? dueDate,
    DateTime? completedAt,
    @Default(0) int position,
    required DateTime createdAt,
    required DateTime updatedAt,
    // Additional fields for UI
    User? assignee,
    User? creator,
  }) = _Task;

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
}

@freezed
class User with _$User {
  const factory User({
    required String id,
    required String email,
    String? fullName,
    String? avatarUrl,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
