import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/supabase_client.dart';
import '../../../../core/constants/app_constants.dart';
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
  bool _isPreviewMode = false;
  late final Future<String?> _updatedByFuture;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.initialDocument?['title'] as String? ?? 'Новый документ',
    );
    _contentController = TextEditingController(
      text: widget.initialDocument?['content'] as String? ?? '',
    );

    final updatedByRaw = widget.initialDocument?['updated_by'] as String?;
    _updatedByFuture = updatedByRaw == null || updatedByRaw.isEmpty
        ? Future.value(null)
        : _fetchUserDisplayName(updatedByRaw);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<dynamic> _invokeGeminiAssistant({
    required Map<String, dynamic> body,
  }) async {
    final client = SupabaseClientService.instance.client;
    final session = client.auth.currentSession;
    final accessToken = session?.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Нет активной сессии. Перезайдите в аккаунт и попробуйте снова.');
    }

    final token = accessToken.startsWith('Bearer ')
        ? accessToken.substring('Bearer '.length)
        : accessToken;

    return client.functions.invoke(
      'gemini-assistant',
      body: body,
      headers: {
        // Supabase platform validates JWT from this header for Edge Functions.
        'Authorization': 'Bearer $token',
        // When overriding headers, ensure apikey is still passed.
        'apikey': AppConstants.supabaseAnonKey,
      },
    );
  }

  Future<String?> _fetchUserDisplayName(String userId) async {
    final res = await SupabaseClientService.instance.rpc(
      functionName: 'find_user_display_name_by_task_and_user',
      params: {
        'p_task_id': widget.taskId,
        'p_user_id': userId,
      },
    );
    if (res == null) return null;
    final value = res.toString();
    return value.trim().isEmpty ? null : value;
  }

  void _wrapSelection(String prefix, String suffix) {
    final selection = _contentController.selection;
    final text = _contentController.text;
    final start = selection.start;
    final end = selection.end;

    if (start < 0 || end < 0 || start > text.length || end > text.length) {
      return;
    }

    // If nothing selected -> insert prefix+suffix and keep cursor in between.
    if (start == end) {
      final newText = text.replaceRange(start, end, '$prefix$suffix');
      _contentController.text = newText;
      _contentController.selection = TextSelection.collapsed(
        offset: start + prefix.length,
      );
      return;
    }

    final selected = text.substring(start, end);
    final newText = text.replaceRange(start, end, '$prefix$selected$suffix');
    _contentController.text = newText;
    _contentController.selection = TextSelection(
      baseOffset: start + prefix.length,
      extentOffset: end + prefix.length,
    );
  }

  void _insertAtCursor(String insert) {
    final selection = _contentController.selection;
    final start = selection.start;
    final end = selection.end;
    final text = _contentController.text;
    if (start < 0 || end < 0 || start > text.length || end > text.length) return;

    final newText = text.replaceRange(start, end, insert);
    _contentController.text = newText;

    final cursor = start + insert.length;
    _contentController.selection = TextSelection.collapsed(offset: cursor);
  }

  Future<void> _insertImageFromGallery() async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;

    setState(() => _isSaving = true);
    try {
      final bytes = await xfile.readAsBytes();
      final fileName = xfile.name;
      final ext = (() {
        final dotIndex = fileName.lastIndexOf('.');
        if (dotIndex == -1 || dotIndex == fileName.length - 1) return 'png';
        return fileName.substring(dotIndex + 1).toLowerCase();
      })();

      String? contentType;
      switch (ext) {
        case 'jpg':
        case 'jpeg':
          contentType = 'image/jpeg';
          break;
        case 'webp':
          contentType = 'image/webp';
          break;
        case 'gif':
          contentType = 'image/gif';
          break;
        case 'png':
        default:
          contentType = 'image/png';
      }

      final client = SupabaseClientService.instance.client;
      final userId = SupabaseClientService.instance.currentUserId;
      if (userId == null) throw Exception('User session expired');

      final path =
          'documents/$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await SupabaseClientService.instance.uploadFileBytes(
        bucket: 'task-attachments',
        path: path,
        bytes: bytes,
        contentType: contentType,
      );

      final publicUrl =
          client.storage.from('task-attachments').getPublicUrl(path);

      _insertAtCursor('\n\n![](${publicUrl})\n\n');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addBulletListToSelection() {
    final selection = _contentController.selection;
    if (selection.start == selection.end) {
      _insertAtCursor('- ');
      return;
    }

    final text = _contentController.text;
    final selected = text.substring(selection.start, selection.end);
    final lines = selected.split('\n');
    final prefixed = lines.map((l) {
      if (l.trim().isEmpty) return l;
      return '- $l';
    }).join('\n');

    _contentController.text = text.replaceRange(
      selection.start,
      selection.end,
      prefixed,
    );

    _contentController.selection = TextSelection(
      baseOffset: selection.start,
      extentOffset: selection.start + prefixed.length,
    );
  }

  void _addNumberedListToSelection() {
    final selection = _contentController.selection;
    if (selection.start == selection.end) {
      _insertAtCursor('1. ');
      return;
    }

    final text = _contentController.text;
    final selected = text.substring(selection.start, selection.end);
    final lines = selected.split('\n');
    var i = 1;
    final prefixed = lines.map((l) {
      if (l.trim().isEmpty) return l;
      final value = '${i.toString()}. $l';
      i++;
      return value;
    }).join('\n');

    _contentController.text = text.replaceRange(
      selection.start,
      selection.end,
      prefixed,
    );

    _contentController.selection = TextSelection(
      baseOffset: selection.start,
      extentOffset: selection.start + prefixed.length,
    );
  }

  void _addHeadingToSelection(int level) {
    final selection = _contentController.selection;
    final marker = '#'.padLeft(level, '#') + ' ';

    if (selection.start == selection.end) {
      _insertAtCursor('${marker}');
      return;
    }

    final text = _contentController.text;
    final selected = text.substring(selection.start, selection.end);
    final lines = selected.split('\n');
    final prefixed = lines.map((l) {
      if (l.trim().isEmpty) return l;
      return '$marker$l';
    }).join('\n');

    _contentController.text = text.replaceRange(
      selection.start,
      selection.end,
      prefixed,
    );
  }

  void _addQuoteToSelection() {
    final selection = _contentController.selection;
    if (selection.start == selection.end) {
      _insertAtCursor('> ');
      return;
    }

    final text = _contentController.text;
    final selected = text.substring(selection.start, selection.end);
    final lines = selected.split('\n');
    final prefixed = lines.map((l) {
      if (l.trim().isEmpty) return l;
      return '> $l';
    }).join('\n');

    _contentController.text = text.replaceRange(
      selection.start,
      selection.end,
      prefixed,
    );
  }

  Future<void> _insertLinkFromDialog() async {
    final selection = _contentController.selection;
    final text = _contentController.text;

    final selectedText = selection.start == selection.end
        ? 'ссылка'
        : text.substring(selection.start, selection.end);

    final urlController = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вставить ссылку'),
        content: TextField(
          controller: urlController,
          decoration: const InputDecoration(
            labelText: 'URL',
            hintText: 'https://example.com',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, urlController.text.trim()),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    if (url == null) return;
    final cleaned = url.trim();
    if (cleaned.isEmpty) return;

    _contentController.selection = selection;
    _insertAtCursor('[$selectedText]($cleaned)');
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
      final response = await _invokeGeminiAssistant(
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
              final response = await _invokeGeminiAssistant(
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: 520,
                    maxHeight: constraints.maxHeight - 32,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _titleController,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(
                          labelText: 'Название документа',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (updatedAt != null)
                        FutureBuilder<String?>(
                          future: _updatedByFuture,
                          builder: (context, snapshot) {
                            final updatedByName = snapshot.data;
                            final updatedByText = updatedByName ?? updatedByRaw;

                            return Text(
                              'Последнее изменение: ${updatedAt.day}.${updatedAt.month}.${updatedAt.year} '
                              '${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}'
                              '${updatedByText != null ? ' • $updatedByText' : ''}',
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            );
                          },
                        ),
                      const SizedBox(height: 12),
                      ToggleButtons(
                        isSelected: [!_isPreviewMode, _isPreviewMode],
                        onPressed: (index) {
                          setState(() => _isPreviewMode = index == 1);
                        },
                        borderRadius: BorderRadius.circular(12),
                        selectedBorderColor: Theme.of(context).colorScheme.primary,
                        fillColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('Редактировать'),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('Просмотр'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _isPreviewMode
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.white,
                                ),
                                child: MarkdownBody(
                                  data: _contentController.text,
                                  selectable: true,
                                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                    p: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              )
                            : Column(
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      IconButton(
                                        tooltip: 'Жирный',
                                        icon: const Icon(Icons.format_bold),
                                        onPressed: () => _wrapSelection('**', '**'),
                                      ),
                                      IconButton(
                                        tooltip: 'Курсив',
                                        icon: const Icon(Icons.format_italic),
                                        onPressed: () => _wrapSelection('*', '*'),
                                      ),
                                      IconButton(
                                        tooltip: 'Зачеркивание',
                                        icon: const Icon(Icons.format_strikethrough),
                                        onPressed: () => _wrapSelection('~~', '~~'),
                                      ),
                                      IconButton(
                                        tooltip: 'Заголовок 1',
                                        icon: const Icon(Icons.title),
                                        onPressed: () => _addHeadingToSelection(1),
                                      ),
                                      IconButton(
                                        tooltip: 'Заголовок 2',
                                        icon: const Icon(Icons.text_fields),
                                        onPressed: () => _addHeadingToSelection(2),
                                      ),
                                      IconButton(
                                        tooltip: 'Маркированный список',
                                        icon: const Icon(Icons.format_list_bulleted),
                                        onPressed: _addBulletListToSelection,
                                      ),
                                      IconButton(
                                        tooltip: 'Нумерованный список',
                                        icon: const Icon(Icons.format_list_numbered),
                                        onPressed: _addNumberedListToSelection,
                                      ),
                                      IconButton(
                                        tooltip: 'Цитата',
                                        icon: const Icon(Icons.format_quote),
                                        onPressed: _addQuoteToSelection,
                                      ),
                                      IconButton(
                                        tooltip: 'Ссылка',
                                        icon: const Icon(Icons.link),
                                        onPressed: _insertLinkFromDialog,
                                      ),
                                      IconButton(
                                        tooltip: 'Картинка',
                                        icon: const Icon(Icons.image_outlined),
                                        onPressed: _isSaving ? null : _insertImageFromGallery,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _contentController,
                                      expands: true,
                                      maxLines: null,
                                      minLines: null,
                                      textAlignVertical: TextAlignVertical.top,
                                      decoration: const InputDecoration(
                                        hintText: 'Введите текст документа (Markdown поддерживается)...',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
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
        ),
      ),
    );
  }
}

