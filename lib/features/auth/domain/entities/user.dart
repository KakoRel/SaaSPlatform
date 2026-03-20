class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
    this.isEmailConfirmed = false,
  });

  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isEmailConfirmed;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      isEmailConfirmed: json['is_email_confirmed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_email_confirmed': isEmailConfirmed,
    };
  }

  AppUser copyWith({
    String? id,
    String? email,
    String? fullName,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isEmailConfirmed,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isEmailConfirmed: isEmailConfirmed ?? this.isEmailConfirmed,
    );
  }
}
