import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/message_model.dart';
import '../models/todo_model.dart';
import '../services/auth_service.dart' show coupleId;
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class SearchScreen extends StatefulWidget {
  final void Function(int) onNavigate;
  /// Called with a message id when the user taps a message result.
  /// The caller (MainShell) is responsible for switching to chat and scrolling.
  final void Function(String messageId)? onSelectMessage;

  const SearchScreen({
    super.key,
    required this.onNavigate,
    this.onSelectMessage,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _firestore = FirestoreService();
  final _searchCtrl = TextEditingController();
  static const _coupleId = coupleId;

  String _query = '';
  List<Message> _allMessages = [];
  List<TodoItem> _allTodos = [];
  bool _loadingMessages = false;
  StreamSubscription<List<TodoItem>>? _todoSub;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    // Load full message history once for search
    _loadMessages();
    _todoSub = _firestore.todoStream(_coupleId).listen((todos) {
      if (mounted) setState(() => _allTodos = todos);
    });
  }

  Future<void> _loadMessages() async {
    setState(() => _loadingMessages = true);
    final all = await _firestore.getAllMessages(_coupleId);
    if (mounted) setState(() { _allMessages = all; _loadingMessages = false; });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _todoSub?.cancel();
    super.dispose();
  }

  List<Message> get _filteredMessages {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return _allMessages
        .where((m) => m.text.toLowerCase().contains(q))
        .toList();
  }

  List<TodoItem> get _filteredTodos {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return _allTodos.where((t) {
      return t.title.toLowerCase().contains(q) ||
          (t.details?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _filteredMessages;
    final todos = _filteredTodos;
    final hasResults = msgs.isNotEmpty || todos.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.15),
                width: 1,
                  ),
                ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: AppTheme.textMuted,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search chats & to-dos…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    if (_query.isNotEmpty) {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppTheme.textMuted,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_loadingMessages)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _query.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_rounded,
                      size: 52, color: AppTheme.textMuted),
                  const SizedBox(height: 12),
                  Text('Search messages and to-dos',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textMuted)),
                ],
              ),
            )
          : !hasResults
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off_rounded,
                          size: 52, color: AppTheme.textMuted),
                      const SizedBox(height: 12),
                      Text('No results for "$_query"',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.textMuted)),
                    ],
                  ),
                )
              : ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    if (msgs.isNotEmpty) ...[
                      _sectionLabel(
                          context, 'Messages', '${msgs.length}'),
                      const SizedBox(height: 8),
                      ...msgs.map((m) => _MessageResult(
                            message: m,
                            query: _query,
                            isMe: m.senderId == _myUid,
                            onTap: () {
                              Navigator.pop(context);
                              widget.onNavigate(1);
                              // After navigation completes, scroll to message
                              if (widget.onSelectMessage != null) {
                                Future.delayed(
                                  const Duration(milliseconds: 300),
                                  () => widget.onSelectMessage!(m.id),
                                );
                              }
                            },
                          )),
                    ],
                    if (todos.isNotEmpty) ...[
                      if (msgs.isNotEmpty) const SizedBox(height: 20),
                      _sectionLabel(
                          context, 'To-dos', '${todos.length}'),
                      const SizedBox(height: 8),
                      ...todos.map((t) => _TodoResult(
                            todo: t,
                            query: _query,
                            onTap: () {
                              Navigator.pop(context);
                              widget.onNavigate(2);
                            },
                          )),
                    ],
                  ],
                ),
    );
  }

  Widget _sectionLabel(BuildContext context, String title, String count) {
    return Row(
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                    color: AppTheme.textMuted, letterSpacing: 0.3)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(count,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ── Message result tile ───────────────────────────────────────────────────────

class _MessageResult extends StatelessWidget {
  final Message message;
  final String query;
  final bool isMe;
  final VoidCallback onTap;

  const _MessageResult({
    required this.message,
    required this.query,
    required this.isMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: isMe
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : AppTheme.primaryLight,
              child: Text(
                isMe ? 'Me' : 'A',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightText(
                    text: message.text,
                    query: query,
                    baseStyle: const TextStyle(
                        fontSize: 14, color: AppTheme.textDark),
                    highlightStyle: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w700,
                        backgroundColor: Color(0xFFFFF3CD)),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    timeago.format(message.sentAt, locale: 'en_short'),
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Todo result tile ──────────────────────────────────────────────────────────

class _TodoResult extends StatelessWidget {
  final TodoItem todo;
  final String query;
  final VoidCallback onTap;

  const _TodoResult({
    required this.todo,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: todo.isDone ? AppTheme.primary : Colors.transparent,
                border: Border.all(
                  color:
                      todo.isDone ? AppTheme.primary : AppTheme.textMuted,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: todo.isDone
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightText(
                    text: todo.title,
                    query: query,
                    baseStyle: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: todo.isDone
                          ? AppTheme.textMuted
                          : AppTheme.textDark,
                      decoration: todo.isDone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                    highlightStyle: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: todo.isDone
                          ? AppTheme.textMuted
                          : AppTheme.textDark,
                      decoration: todo.isDone
                          ? TextDecoration.lineThrough
                          : null,
                      backgroundColor: const Color(0xFFFFF3CD),
                    ),
                  ),
                  if (todo.details?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    _HighlightText(
                      text: todo.details!,
                      query: query,
                      baseStyle: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                      highlightStyle: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                          backgroundColor: Color(0xFFFFF3CD)),
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Highlight text widget ─────────────────────────────────────────────────────

class _HighlightText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle baseStyle;
  final TextStyle highlightStyle;
  final int? maxLines;

  const _HighlightText({
    required this.text,
    required this.query,
    required this.baseStyle,
    required this.highlightStyle,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text,
          style: baseStyle,
          maxLines: maxLines,
          overflow:
              maxLines != null ? TextOverflow.ellipsis : TextOverflow.clip);
    }

    final lower = text.toLowerCase();
    final queryLower = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    int idx = lower.indexOf(queryLower);
    while (idx != -1) {
      if (idx > start) {
        spans.add(TextSpan(
            text: text.substring(start, idx), style: baseStyle));
      }
      spans.add(TextSpan(
          text: text.substring(idx, idx + query.length),
          style: highlightStyle));
      start = idx + query.length;
      idx = lower.indexOf(queryLower, start);
    }
    if (start < text.length) {
      spans.add(
          TextSpan(text: text.substring(start), style: baseStyle));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow:
          maxLines != null ? TextOverflow.ellipsis : TextOverflow.clip,
    );
  }
}
