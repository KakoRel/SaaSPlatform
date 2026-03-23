import 'package:flutter/material.dart';

import '../../../../core/services/supabase_client.dart';

class ProjectStructureScreen extends StatefulWidget {
  const ProjectStructureScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  State<ProjectStructureScreen> createState() => _ProjectStructureScreenState();
}

class _ProjectStructureScreenState extends State<ProjectStructureScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> _boards = [];

  String? _selectedDepartmentId;
  String? _selectedFolderId;

  final _departmentNameController = TextEditingController();
  final _folderNameController = TextEditingController();
  final _boardNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadAll());
  }

  @override
  void dispose() {
    _departmentNameController.dispose();
    _folderNameController.dispose();
    _boardNameController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      await _loadDepartments();
      await _loadFolders();
      await _loadBoards();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDepartments() async {
    final items = await SupabaseClientService.instance.fetchList<Map<String, dynamic>>(
      tableName: 'departments',
      select: '*',
      filters: [
        QueryFilter('project_id', 'eq', widget.projectId),
      ],
      fromJson: (json) => json,
    );
    _departments = items;
    _selectedDepartmentId ??= items.isNotEmpty ? items.first['id'] as String? : null;
  }

  Future<void> _loadFolders() async {
    if (_selectedDepartmentId == null) {
      _folders = [];
      _selectedFolderId = null;
      return;
    }

    final items = await SupabaseClientService.instance.fetchList<Map<String, dynamic>>(
      tableName: 'project_folders',
      select: '*',
      filters: [
        QueryFilter('project_id', 'eq', widget.projectId),
        QueryFilter('department_id', 'eq', _selectedDepartmentId),
      ],
      fromJson: (json) => json,
    );

    _folders = items;
    _selectedFolderId ??= items.isNotEmpty ? items.first['id'] as String? : null;
  }

  Future<void> _loadBoards() async {
    final deptId = _selectedDepartmentId;
    final folderId = _selectedFolderId;

    final List<QueryFilter> filters = [
      QueryFilter('project_id', 'eq', widget.projectId),
    ];

    if (deptId != null && deptId.isNotEmpty) {
      filters.add(QueryFilter('department_id', 'eq', deptId));
    }
    if (folderId != null && folderId.isNotEmpty) {
      filters.add(QueryFilter('folder_id', 'eq', folderId));
    }

    final items = await SupabaseClientService.instance.fetchList<Map<String, dynamic>>(
      tableName: 'boards',
      select: '*',
      filters: filters,
      fromJson: (json) => json,
    );

    _boards = items;
  }

  Future<void> _createDepartment() async {
    final name = _departmentNameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await SupabaseClientService.instance.insert<Map<String, dynamic>>(
        tableName: 'departments',
        data: {
          'project_id': widget.projectId,
          'name': name,
          'created_by': SupabaseClientService.instance.currentUserId,
        },
        fromJson: (json) => json,
        select: '*',
      );
      _departmentNameController.clear();
      await _loadAll();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _createFolder() async {
    final name = _folderNameController.text.trim();
    final deptId = _selectedDepartmentId;
    if (name.isEmpty || deptId == null) return;

    setState(() => _isSaving = true);
    try {
      await SupabaseClientService.instance.insert<Map<String, dynamic>>(
        tableName: 'project_folders',
        data: {
          'project_id': widget.projectId,
          'department_id': deptId,
          'name': name,
          'created_by': SupabaseClientService.instance.currentUserId,
        },
        fromJson: (json) => json,
        select: '*',
      );
      _folderNameController.clear();
      await _loadFolders();
      await _loadBoards();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _createBoard() async {
    final name = _boardNameController.text.trim();
    final deptId = _selectedDepartmentId;
    final folderId = _selectedFolderId;
    if (name.isEmpty || deptId == null) return;

    setState(() => _isSaving = true);
    try {
      await SupabaseClientService.instance.insert<Map<String, dynamic>>(
        tableName: 'boards',
        data: {
          'project_id': widget.projectId,
          'department_id': deptId,
          'folder_id': folderId,
          'name': name,
          'created_by': SupabaseClientService.instance.currentUserId,
        },
        fromJson: (json) => json,
        select: '*',
      );
      _boardNameController.clear();
      await _loadBoards();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Структура: ${widget.projectName}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '1) Отделы (Departments)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _departmentNameController,
                        decoration: const InputDecoration(
                          labelText: 'Название отдела',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _createDepartment,
                      child: const Text('Создать'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in _departments)
                      ChoiceChip(
                        label: Text(d['name']?.toString() ?? ''),
                        selected: (_selectedDepartmentId != null) && (d['id']?.toString() == _selectedDepartmentId),
                        onSelected: (selected) {
                          if (!selected) return;
                          setState(() {
                            _selectedDepartmentId = d['id']?.toString();
                            _selectedFolderId = null;
                          });
                          _loadFolders().then((_) => _loadBoards());
                        },
                      ),
                  ],
                ),
                const Divider(height: 32),
                const Text(
                  '2) Папки (Folders)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_selectedDepartmentId == null)
                  const Text('Сначала выберите отдел (или создайте новый).')
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDepartmentId,
                    decoration: const InputDecoration(
                      labelText: 'Отдел',
                      border: OutlineInputBorder(),
                    ),
                    items: _departments
                        .map(
                          (d) => DropdownMenuItem<String>(
                            value: d['id']?.toString(),
                            child: Text(d['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      setState(() {
                        _selectedDepartmentId = v;
                        _selectedFolderId = null;
                      });
                      await _loadFolders();
                      await _loadBoards();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _folderNameController,
                          decoration: const InputDecoration(
                            labelText: 'Название папки',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _createFolder,
                        child: const Text('Создать'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedFolderId,
                    decoration: const InputDecoration(
                      labelText: 'Папка (для досок)',
                      border: OutlineInputBorder(),
                    ),
                    items: _folders
                        .map(
                          (f) => DropdownMenuItem<String>(
                            value: f['id']?.toString(),
                            child: Text(f['name']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      setState(() => _selectedFolderId = v);
                      await _loadBoards();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                const Divider(height: 32),
                const Text(
                  '3) Доски (Boards)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_selectedDepartmentId == null)
                  const Text('Выберите отдел и (опционально) папку.')
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _boardNameController,
                          decoration: const InputDecoration(
                            labelText: 'Название доски',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _createBoard,
                        child: const Text('Создать'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in _boards)
                        Chip(
                          label: Text(b['name']?.toString() ?? ''),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

