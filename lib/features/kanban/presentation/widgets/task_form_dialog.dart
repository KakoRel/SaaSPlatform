import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../domain/entities/task.dart';
import '../../providers/kanban_provider.dart';
import '../../../projects/providers/projects_provider.dart';

class TaskFormDialog extends ConsumerStatefulWidget {
  const TaskFormDialog({super.key, this.task, this.initialStatus});

  final Task? task;
  final TaskStatus? initialStatus;

  @override
  ConsumerState<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends ConsumerState<TaskFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TaskPriority _priority;
  late TaskStatus _status;
  String? _assigneeId;
  DateTime? _dueDate;
  
  Uint8List? _imageBytes;
  String? _imageExtension;
  String? _currentImageUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descriptionController = TextEditingController(text: widget.task?.description ?? '');
    _priority = widget.task?.priority ?? TaskPriority.medium;
    _status = widget.task?.status ?? widget.initialStatus ?? TaskStatus.todo;
    _assigneeId = widget.task?.assigneeId;
    _dueDate = widget.task?.dueDate;
    _currentImageUrl = widget.task?.imageUrl;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imageExtension = image.path.split('.').last;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedProject = ref.watch(selectedProjectProvider);
    final projectsNotifier = ref.read(projectsProvider.notifier);

    return AlertDialog(
      title: Text(widget.task == null ? 'Создать задачу' : 'Редактировать задачу'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Название'),
                validator: (value) => value == null || value.isEmpty ? 'Пожалуйста, введите название' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Описание'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<TaskPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Приоритет'),
                items: TaskPriority.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(_getPriorityLabel(p)),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _priority = val!),
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: selectedProject != null ? projectsNotifier.getProjectMembers(selectedProject.id) : Future.value([]),
                builder: (context, snapshot) {
                  final members = snapshot.data ?? [];
                  return DropdownButtonFormField<String?>(
                    initialValue: _assigneeId,
                    decoration: const InputDecoration(labelText: 'Исполнитель'),
                    hint: const Text('Не назначен'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Не назначен')),
                      ...members.map((m) {
                        final user = m['users'] as Map<String, dynamic>?;
                        final name = user?['full_name'] as String? ?? user?['email'] as String? ?? 'Unknown';
                        return DropdownMenuItem(
                          value: m['user_id'] as String,
                          child: Text(name),
                        );
                      }),
                    ],
                    onChanged: (val) => setState(() => _assigneeId = val),
                  );
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_dueDate == null ? 'Нет срока' : 'Срок: ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: _selectDate,
              ),
              const SizedBox(height: 16),
              _buildImageSection(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isUploading ? null : _submit,
          child: _isUploading 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(widget.task == null ? 'Создать' : 'Сохранить'),
        ),
      ],
    );
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Фото к задаче', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_imageBytes != null)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_imageBytes!, height: 150, width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() {
                      _imageBytes = null;
                      _imageExtension = null;
                    }),
                  ),
                ),
              ),
            ],
          )
        else if (_currentImageUrl != null)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(_currentImageUrl!, height: 150, width: double.infinity, fit: BoxFit.cover),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() => _currentImageUrl = null),
                  ),
                ),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Добавить фото'),
          ),
      ],
    );
  }

  String _getPriorityLabel(TaskPriority p) {
    switch (p) {
      case TaskPriority.low: return 'НИЗКИЙ';
      case TaskPriority.medium: return 'СРЕДНИЙ';
      case TaskPriority.high: return 'ВЫСОКИЙ';
      case TaskPriority.urgent: return 'СРОЧНЫЙ';
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isUploading = true);
      
      final notifier = ref.read(kanbanProvider.notifier);
      String? imageUrl = _currentImageUrl;

      if (_imageBytes != null && _imageExtension != null) {
        // Use a temp ID for filename if creating new task
        final tempId = widget.task?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
        imageUrl = await notifier.uploadTaskImage(tempId, _imageBytes!, _imageExtension!);
      }

      if (widget.task == null) {
        await notifier.createTask(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          priority: _priority,
          assigneeId: _assigneeId,
          dueDate: _dueDate,
          imageUrl: imageUrl,
        );
      } else {
        await notifier.updateTask(
          taskId: widget.task!.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          priority: _priority,
          assigneeId: _assigneeId,
          dueDate: _dueDate,
          status: _status,
          imageUrl: imageUrl,
        );
      }
      
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
