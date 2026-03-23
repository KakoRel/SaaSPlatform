class ProjectBoard {
  const ProjectBoard({
    required this.id,
    required this.projectId,
    required this.name,
    this.departmentId,
    this.departmentName,
    this.folderId,
    this.folderName,
  });

  final String id;
  final String projectId;
  final String name;
  final String? departmentId;
  final String? departmentName;
  final String? folderId;
  final String? folderName;

  factory ProjectBoard.fromJson(Map<String, dynamic> json) {
    return ProjectBoard(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String,
      departmentId: json['department_id'] as String?,
      departmentName: json['department_name'] as String?,
      folderId: json['folder_id'] as String?,
      folderName: json['folder_name'] as String?,
    );
  }
}

