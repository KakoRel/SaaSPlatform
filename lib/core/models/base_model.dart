class BaseModel {
  const BaseModel({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory BaseModel.fromJson(Map<String, dynamic> json) {
    return BaseModel(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
