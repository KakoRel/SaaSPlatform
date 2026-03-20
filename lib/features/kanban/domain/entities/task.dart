enum TaskPriority {
  low,
  medium,
  high,
  urgent;

  static TaskPriority fromString(String value) {
    return TaskPriority.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TaskPriority.medium,
    );
  }
}

enum TaskStatus {
  todo,
  inProgress,
  review,
  done;

  String toDbValue() {
    switch (this) {
      case TaskStatus.todo:
        return 'todo';
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.review:
        return 'review';
      case TaskStatus.done:
        return 'done';
    }
  }

  static TaskStatus fromDbValue(String value) {
    switch (value) {
      case 'todo':
        return TaskStatus.todo;
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'review':
        return TaskStatus.review;
      case 'done':
        return TaskStatus.done;
      default:
        return TaskStatus.todo;
    }
  }
}

class TaskMember {
  const TaskMember({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;

  factory TaskMember.fromJson(Map<String, dynamic> json) {
    return TaskMember(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

class Task {
  const Task({
    required this.id,
    required this.projectId,
    required this.title,
    this.description,
    this.assigneeId,
    required this.creatorId,
    this.status = TaskStatus.todo,
    this.priority = TaskPriority.medium,
    this.dueDate,
    this.completedAt,
    this.position = 0,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
    this.assignee,
    this.creator,
  });

  final String id;
  final String projectId;
  final String title;
  final String? description;
  final String? assigneeId;
  final String creatorId;
  final TaskStatus status;
  final TaskPriority priority;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final int position;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TaskMember? assignee;
  final TaskMember? creator;

  factory Task.fromJson(Map<String, dynamic> json) {
    final assigneeIdRaw = json['assignee_id'] as String?;
    final assigneeName = json['assignee_name'] as String?;
    final assigneeEmail = json['assignee_email'] as String?;

    final creatorName = json['creator_name'] as String?;
    final creatorEmail = json['creator_email'] as String?;

    return Task(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      assigneeId: json['assignee_id'] as String?,
      creatorId: json['creator_id'] as String,
      status: TaskStatus.fromDbValue(json['status'] as String? ?? 'todo'),
      priority: TaskPriority.fromString(json['priority'] as String? ?? 'medium'),
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
      position: json['position'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      imageUrl: json['image_url'] as String?,
      // Assignee may have `full_name` == null, but `email` can still be present.
      // Поэтому создаём TaskMember если есть хотя бы email.
      assignee: (assigneeIdRaw != null &&
              (assigneeName != null ||
                  (assigneeEmail != null && assigneeEmail.isNotEmpty)))
          ? TaskMember(
              id: assigneeIdRaw,
              email: assigneeEmail ?? '',
              fullName: assigneeName,
            )
          : null,
      creator: json['creator_id'] != null &&
              (creatorName != null ||
                  (creatorEmail != null && creatorEmail.isNotEmpty))
          ? TaskMember(
              id: json['creator_id'] as String,
              email: creatorEmail ?? '',
              fullName: creatorName,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'project_id': projectId,
      'title': title,
      'description': description,
      'assignee_id': assigneeId,
      'creator_id': creatorId,
      'status': status.toDbValue(),
      'priority': priority.name,
      'due_date': dueDate?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'position': position,
      'image_url': imageUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Task copyWith({
    String? id,
    String? projectId,
    String? title,
    String? description,
    String? assigneeId,
    String? creatorId,
    TaskStatus? status,
    TaskPriority? priority,
    DateTime? dueDate,
    DateTime? completedAt,
    int? position,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    TaskMember? assignee,
    TaskMember? creator,
  }) {
    return Task(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      description: description ?? this.description,
      assigneeId: assigneeId ?? this.assigneeId,
      creatorId: creatorId ?? this.creatorId,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
      position: position ?? this.position,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      assignee: assignee ?? this.assignee,
      creator: creator ?? this.creator,
    );
  }
}
