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
    final items = await SupabaseClientService.instance.fetchList<Map<String, dynamic>>(
      tableName: 'project_folders',
      select: '*',
      filters: [QueryFilter('project_id', 'eq', widget.projectId)],
      fromJson: (json) => json,
    );
    _folders = items;
    if (_selectedFolderId != null &&
        !_folders.any((f) => f['id']?.toString() == _selectedFolderId)) {
      _selectedFolderId = null;
    }
  }

  Future<void> _loadBoards() async {
    _boards = await SupabaseClientService.instance.fetchList<Map<String, dynamic>>(
      tableName: 'boards',
      select: '*',
      filters: [QueryFilter('project_id', 'eq', widget.projectId)],
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

  Future<void> _renameItem({
    required String tableName,
    required String id,
    required String currentName,
  }) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Новое название'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;
    await SupabaseClientService.instance.update<Map<String, dynamic>>(
      tableName: tableName,
      id: id,
      data: {'name': newName},
      fromJson: (json) => json,
    );
    await _loadAll();
  }

  Future<void> _deleteItem({
    required String tableName,
    required String id,
    required String title,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить $title'),
        content: const Text('Действие необратимо. Продолжить?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SupabaseClientService.instance.delete(tableName: tableName, id: id);
    await _loadAll();
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
                final depBoards = _boards.where(
                  (b) => b['department_id']?.toString() == depId && b['folder_id'] == null,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '• $depName',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => _renameItem(
                              tableName: 'departments',
                              id: depId ?? '',
                              currentName: depName,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _deleteItem(
                              tableName: 'departments',
                              id: depId ?? '',
                              title: 'отдел',
                            ),
                          ),
                        ],
                      ),
                      for (final f in depFolders)
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 16, top: 2),
                              child: Row(
                                children: [
                                  Expanded(child: Text('↳ Папка: ${f['name'] ?? ''}')),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 16),
                                    onPressed: () => _renameItem(
                                      tableName: 'project_folders',
                                      id: f['id']?.toString() ?? '',
                                      currentName: f['name']?.toString() ?? '',
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 16),
                                    onPressed: () => _deleteItem(
                                      tableName: 'project_folders',
                                      id: f['id']?.toString() ?? '',
                                      title: 'папку',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ..._boards
                                .where((b) => b['folder_id']?.toString() == f['id']?.toString())
                                .map(
                                  (b) => Padding(
                                    padding: const EdgeInsets.only(left: 32, top: 2),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text('↳ Доска: ${b['name'] ?? ''}'),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 16),
                                          onPressed: () => _renameItem(
                                            tableName: 'boards',
                                            id: b['id']?.toString() ?? '',
                                            currentName: b['name']?.toString() ?? '',
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 16),
                                          onPressed: () => _deleteItem(
                                            tableName: 'boards',
                                            id: b['id']?.toString() ?? '',
                                            title: 'доску',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      for (final b in depBoards)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 2),
                          child: Row(
                            children: [
                              Expanded(child: Text('↳ Доска: ${b['name'] ?? ''}')),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                onPressed: () => _renameItem(
                                  tableName: 'boards',
                                  id: b['id']?.toString() ?? '',
                                  currentName: b['name']?.toString() ?? '',
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 16),
                                onPressed: () => _deleteItem(
                                  tableName: 'boards',
                                  id: b['id']?.toString() ?? '',
                                  title: 'доску',
                                ),
                              ),
                            ],
                          ),
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

