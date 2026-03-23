import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_client.dart';
import '../../providers/kanban_provider.dart';

class DocumentEditorScreen extends ConsumerStatefulWidget {
  const DocumentEditorScreen({
    super.key,
    required this.taskId,
    this.initialDocument,
  });

  final String taskId;
  final Map<String, dynamic>? initialDocument;

  @override
  ConsumerState<DocumentEditorScreen> createState() => _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends ConsumerState<DocumentEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  bool _isSaving = false;
  bool _isAiWorking = false;
  final List<Map<String, String>> _aiChat = [];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.initialDocument?['title'] as String? ?? 'Новый документ',
    );
    _contentController = TextEditingController(
      text: widget.initialDocument?['content'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final notifier = ref.read(kanbanProvider.notifier);

    try {
      final existingId = widget.initialDocument?['id'] as String?;
      if (existingId == null) {
        await notifier.createDocument(
          taskId: widget.taskId,
          title: _titleController.text.trim(),
          content: _contentController.text,
        );
      } else {
        await notifier.updateDocument(
          documentId: existingId,
          title: _titleController.text.trim(),
          content: _contentController.text,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Документ сохранен')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _improveWithAi() async {
    setState(() => _isAiWorking = true);
    try {
      final response = await SupabaseClientService.instance.client.functions.invoke(
        'gemini-assistant',
        body: {
          'action': 'improve',
          'text': _contentController.text,
          'instruction':
              'Улучши структуру и читаемость текста, сохрани смысл, добавь четкие подзаголовки и короткие абзацы.',
        },
      );

      final data = response.data;
      final improved = data is Map<String, dynamic> ? data['text'] as String? : null;
      if (improved != null && improved.isNotEmpty) {
        _contentController.text = improved;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAiWorking = false);
    }
  }

  Future<void> _openAiDialog() async {
    final inputController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> sendMessage() async {
            final prompt = inputController.text.trim();
            if (prompt.isEmpty) return;

            setDialogState(() {
              _aiChat.add({'role': 'user', 'content': prompt});
            });
            inputController.clear();

            try {
              final response = await SupabaseClientService.instance.client.functions.invoke(
                'gemini-assistant',
                body: {
                  'action': 'chat',
                  'text': _contentController.text,
                  'messages': _aiChat,
                  'prompt': prompt,
                },
              );
              final data = response.data;
              final text = data is Map<String, dynamic> ? data['text'] as String? : null;
              setDialogState(() {
                _aiChat.add({
                  'role': 'assistant',
                  'content': text ?? 'Не удалось получить ответ.',
                });
              });
            } catch (e) {
              setDialogState(() {
                _aiChat.add({'role': 'assistant', 'content': 'Ошибка: $e'});
              });
            }
          }

          return Dialog(
            child: SizedBox(
              width: 700,
              height: 520,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'AI диалог по документу',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _aiChat.length,
                      itemBuilder: (context, index) {
                        final msg = _aiChat[index];
                        final isUser = msg['role'] == 'user';
                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(10),
                            constraints: const BoxConstraints(maxWidth: 520),
                            decoration: BoxDecoration(
                              color: isUser ? Colors.blue[50] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(msg['content'] ?? ''),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: inputController,
                            decoration: const InputDecoration(
                              hintText: 'Например: Сделай краткую выжимку',
                            ),
                            onSubmitted: (_) => sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: sendMessage,
                          child: const Text('Отправить'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    inputController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final updatedAtRaw = widget.initialDocument?['updated_at'] as String?;
    final updatedByRaw = widget.initialDocument?['updated_by'] as String?;
    final updatedAt =
        updatedAtRaw != null ? DateTime.tryParse(updatedAtRaw)?.toLocal() : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialDocument == null ? 'Новый документ' : 'Редактор документа'),
        actions: [
          TextButton.icon(
            onPressed: _isAiWorking ? null : _improveWithAi,
            icon: _isAiWorking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            label: const Text('Улучшить с AI'),
          ),
          IconButton(
            onPressed: _openAiDialog,
            icon: const Icon(Icons.forum_outlined),
            tooltip: 'AI диалог',
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Название документа',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (updatedAt != null)
              Text(
                'Последнее изменение: ${updatedAt.day}.${updatedAt.month}.${updatedAt.year} ${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}'
                '${updatedByRaw != null ? ' (user: $updatedByRaw)' : ''}',
                style: const TextStyle(color: Colors.grey),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _contentController,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'Введите текст документа...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

