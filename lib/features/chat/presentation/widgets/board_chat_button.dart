import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/supabase_client.dart';

class BoardChatButton extends StatefulWidget {
  const BoardChatButton({
    super.key,
    required this.boardId,
  });

  final String? boardId;

  @override
  State<BoardChatButton> createState() => _BoardChatButtonState();
}

class _BoardChatButtonState extends State<BoardChatButton> {
  int _unreadCount = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _schedulePolling();
  }

  @override
  void didUpdateWidget(covariant BoardChatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boardId != widget.boardId) {
      _refreshUnread();
    }
  }

  void _schedulePolling() {
    _refreshUnread();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshUnread());
  }

  Future<void> _refreshUnread() async {
    final boardId = widget.boardId;
    final userId = SupabaseClientService.instance.currentUserId;
    if (!mounted) return;
    if (boardId == null || userId == null) {
      setState(() => _unreadCount = 0);
      return;
    }

    final client = SupabaseClientService.instance.client;
    final readState = await client
        .from('board_chat_reads')
        .select('last_read_at')
        .eq('board_id', boardId)
        .eq('user_id', userId)
        .maybeSingle();

    final lastRead = DateTime.tryParse(readState?['last_read_at']?.toString() ?? '');

    final allMessages = await client
        .from('board_chat_messages')
        .select('id,user_id,created_at')
        .eq('board_id', boardId)
        .order('created_at', ascending: false)
        .limit(200);

    final unread = (allMessages as List)
        .whereType<Map<String, dynamic>>()
        .where((m) {
          if (m['user_id']?.toString() == userId) return false;
          final createdAt = DateTime.tryParse(m['created_at']?.toString() ?? '');
          if (createdAt == null) return false;
          if (lastRead == null) return true;
          return createdAt.isAfter(lastRead);
        })
        .length;

    if (!mounted) return;
    setState(() => _unreadCount = unread);
  }

  Future<void> _markAsRead() async {
    final boardId = widget.boardId;
    final userId = SupabaseClientService.instance.currentUserId;
    if (boardId == null || userId == null) return;
    final client = SupabaseClientService.instance.client;
    await client.from('board_chat_reads').upsert({
      'board_id': boardId,
      'user_id': userId,
      'last_read_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _openChatPanel() async {
    final boardId = widget.boardId;
    if (boardId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите доску для чата')),
      );
      return;
    }

    await _markAsRead();
    if (mounted) setState(() => _unreadCount = 0);

    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Board chat',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _BoardChatPanel(boardId: boardId);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final offset = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return SlideTransition(position: offset, child: child);
      },
    );

    await _markAsRead();
    await _refreshUnread();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline),
          tooltip: 'Чат доски',
          onPressed: _openChatPanel,
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _BoardChatPanel extends StatefulWidget {
  const _BoardChatPanel({required this.boardId});

  final String boardId;

  @override
  State<_BoardChatPanel> createState() => _BoardChatPanelState();
}

class _BoardChatPanelState extends State<_BoardChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _reloadMessages(silent: true);
    });
    _reloadMessages(silent: false);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadMessages() async {
    final client = SupabaseClientService.instance.client;
    final messages = await client
        .from('board_chat_messages')
        .select('id, message, created_at, user_id')
        .eq('board_id', widget.boardId)
        .order('created_at', ascending: true)
        .limit(300);

    final list = (messages as List).whereType<Map<String, dynamic>>().toList();
    final userIds = list
        .map((m) => m['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final usersById = <String, Map<String, dynamic>>{};
    for (final userId in userIds) {
      final user = await SupabaseClientService.instance.fetchSingle<Map<String, dynamic>>(
        tableName: 'users',
        select: 'id,full_name,email,avatar_url',
        fromJson: (json) => json,
        filters: [QueryFilter('id', 'eq', userId)],
      );
      if (user != null) usersById[userId] = user;
    }

    return list.map((m) {
      final userId = m['user_id']?.toString() ?? '';
      return {
        ...m,
        'user': usersById[userId],
      };
    }).toList();
  }

  Future<void> _reloadMessages({required bool silent}) async {
    try {
      final list = await _loadMessages();
      if (!mounted) return;

      // Avoid visible flicker: update only if something really changed.
      final changed = _messages.length != list.length ||
          (list.isNotEmpty &&
              (_messages.isEmpty || _messages.last['id'] != list.last['id']));

      if (!changed && silent) return;

      final previousLength = _messages.length;
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _isLoading = false;
      });

      final hasNewMessage = _messages.length > previousLength;
      if (hasNewMessage || !silent) {
        _scheduleAutoScrollToBottom();
      }
    } catch (_) {
      // Keep old messages on errors.
      if (!silent && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final userId = SupabaseClientService.instance.currentUserId;
    if (userId == null) return;

    await SupabaseClientService.instance.client.from('board_chat_messages').insert({
      'board_id': widget.boardId,
      'user_id': userId,
      'message': text,
    });
    _controller.clear();
    await _reloadMessages(silent: true);
    _scheduleAutoScrollToBottom();
  }

  void _scheduleAutoScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollToBottom());
  }

  void _autoScrollToBottom() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    final distanceFromBottom = maxExtent - position.pixels;
    final isNearBottom = distanceFromBottom <= 140;

    // Do not hijack scroll when user is reading older messages.
    if (!isNearBottom && _messages.length > 5) return;

    _scrollController.animateTo(
      maxExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = SupabaseClientService.instance.currentUserId;
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: const Color(0xFF0D1118),
        child: SizedBox(
          width: 420,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Чат доски',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading && _messages.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final m = _messages[index];
                            final isMine = m['user_id']?.toString() == myId;
                            final user = m['user'] as Map<String, dynamic>?;
                            final name = user?['full_name']?.toString() ??
                                user?['email']?.toString() ??
                                'Пользователь';
                            return Align(
                              alignment:
                                  isMine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                constraints: const BoxConstraints(maxWidth: 300),
                                decoration: BoxDecoration(
                                  color: isMine
                                      ? Colors.blue.withValues(alpha: 0.18)
                                      : Colors.white12,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      m['message']?.toString() ?? '',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Сообщение...',
                            hintStyle: TextStyle(color: Colors.white54),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _sendMessage,
                        icon: const Icon(Icons.send, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

