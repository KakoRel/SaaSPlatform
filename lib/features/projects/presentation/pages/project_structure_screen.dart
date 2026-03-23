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
    Future.microtask(_loadAll);
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
      filters: [QueryFilter('project_id', 'eq', widget.projectId)],
      fromJson: (json) => json,
    );
    _departments = items;
    _selectedDepartmentId ??= items.isNotEmpty ? items.first['id'] as String? : null;
  }

  Future<void> _loadFolders() async {
    final depId = _selectedDepartmentId;
    if (depId == null) {
      _folders = [];
      _selectedFolderId = null;
      return;
    }
    final items = await SupabaseClientService.instance.fetchList<Map<String, dynamic>>(
      tableName: 'project_folders',
      select: '*',
      filters: [
        QueryFilter('project_id', 'eq', widget.projectId),
        QueryFilter('department_id', 'eq', depId),
      ],
      fromJson: (json) => json,
    );
    _folders = items;
    _selectedFolderId ??= items.isNotEmpty ? items.first['id'] as String? : null;
  }

  Future<void> _loadBoards() async {
    final filters = <QueryFilter>[
      QueryFilter('project_id', 'eq', widget.projectId),
      if (_selectedDepartmentId != null) QueryFilter('department_id', 'eq', _selectedDepartmentId),
      if (_selectedFolderId != null) QueryFilter('folder_id', 'eq', _selectedFolderId),
    ];
    _boards = await SupabaseClientService.instance.fetchList<Map<String, dynamic>>(
      tableName: 'boards',
      select: '*',
      filters: filters,
      fromJson: (json) => json,
    );
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
      );
      _departmentNameController.clear();
      await _loadAll();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _createFolder() async {
    final name = _folderNameController.text.trim();
    if (name.isEmpty || _selectedDepartmentId == null) return;
    setState(() => _isSaving = true);
    try {
      await SupabaseClientService.instance.insert<Map<String, dynamic>>(
        tableName: 'project_folders',
        data: {
          'project_id': widget.projectId,
          'department_id': _selectedDepartmentId,
          'name': name,
          'created_by': SupabaseClientService.instance.currentUserId,
        },
        fromJson: (json) => json,
      );
      _folderNameController.clear();
      await _loadFolders();
      await _loadBoards();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _createBoard() async {
    final name = _boardNameController.text.trim();
    if (name.isEmpty || _selectedDepartmentId == null) return;
    setState(() => _isSaving = true);
    try {
      await SupabaseClientService.instance.insert<Map<String, dynamic>>(
        tableName: 'boards',
        data: {
          'project_id': widget.projectId,
          'department_id': _selectedDepartmentId,
          'folder_id': _selectedFolderId,
          'name': name,
          'created_by': SupabaseClientService.instance.currentUserId,
        },
        fromJson: (json) => json,
      );
      _boardNameController.clear();
      await _loadBoards();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Структура: ${widget.projectName}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHierarchyCard(),
                    const SizedBox(height: 12),
                    _buildDepartmentsCard(),
                    const SizedBox(height: 12),
                    _buildFoldersCard(),
                    const SizedBox(height: 12),
                    _buildBoardsCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHierarchyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Текущая структура',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (_departments.isEmpty)
              const Text('Пока пусто. Создайте первый отдел.')
            else
              ..._departments.map((d) {
                final depId = d['id']?.toString();
                final depName = d['name']?.toString() ?? 'Без названия';
                final depFolders = _folders.where((f) => f['department_id']?.toString() == depId);
                final depBoards = _boards.where((b) => b['department_id']?.toString() == depId);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• $depName', style: const TextStyle(fontWeight: FontWeight.w600)),
                      for (final f in depFolders)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 2),
                          child: Text('↳ Папка: ${f['name'] ?? ''}'),
                        ),
                      for (final b in depBoards)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 2),
                          child: Text('↳ Доска: ${b['name'] ?? ''}'),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1) Отделы', style: TextStyle(fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in _departments)
                  ChoiceChip(
                    label: Text(d['name']?.toString() ?? ''),
                    selected: d['id']?.toString() == _selectedDepartmentId,
                    onSelected: (selected) async {
                      if (!selected) return;
                      setState(() {
                        _selectedDepartmentId = d['id']?.toString();
                        _selectedFolderId = null;
                      });
                      await _loadFolders();
                      await _loadBoards();
                      if (mounted) setState(() {});
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoldersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('2) Папки', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_selectedDepartmentId == null)
              const Text('Сначала выберите отдел.')
            else ...[
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
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in _folders)
                    ChoiceChip(
                      label: Text(f['name']?.toString() ?? ''),
                      selected: f['id']?.toString() == _selectedFolderId,
                      onSelected: (selected) async {
                        if (!selected) return;
                        setState(() => _selectedFolderId = f['id']?.toString());
                        await _loadBoards();
                        if (mounted) setState(() {});
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBoardsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('3) Доски', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_selectedDepartmentId == null)
              const Text('Выберите отдел.')
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
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in _boards)
                    Chip(label: Text(b['name']?.toString() ?? '')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

