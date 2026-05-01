import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/todo_model.dart';
import '../models/comment_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final _firestore = FirestoreService();
  final _auth = AuthService();
  final _textCtrl = TextEditingController();
  static const String _coupleId = coupleId;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _showAddDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add to list', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _textCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'What needs doing?'),
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _add, child: const Text('Add')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    Navigator.pop(context);
    await _firestore.addTodo(
      _coupleId,
      TodoItem(
        id: const Uuid().v4(),
        title: text,
        isDone: false,
        createdBy: _myUid,
        createdAt: DateTime.now(),
      ),
    );
  }

  void _openDetail(TodoItem todo) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TodoDetailSheet(
        todo: todo,
        coupleId: _coupleId,
        firestore: _firestore,
        myName: _auth.myName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Our List')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<TodoItem>>(
        stream: _firestore.todoStream(_coupleId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final todos = snap.data!;
          final pending = todos.where((t) => !t.isDone).toList();
          final done = todos.where((t) => t.isDone).toList();

          if (todos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 48, color: AppTheme.textMuted),
                  const SizedBox(height: 12),
                  Text('No items yet — add something!',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textMuted)),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            children: [
              if (pending.isNotEmpty) ...[
                _sectionLabel('To do'),
                const SizedBox(height: 8),
                ...pending.map((t) => _TodoTile(
                      todo: t,
                      coupleId: _coupleId,
                      firestore: _firestore,
                      onTap: () => _openDetail(t),
                    )),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 20),
                _sectionLabel('Done'),
                const SizedBox(height: 8),
                ...done.map((t) => _TodoTile(
                      todo: t,
                      coupleId: _coupleId,
                      firestore: _firestore,
                      onTap: () => _openDetail(t),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppTheme.textMuted, letterSpacing: 0.3),
      );
}

// ── Todo tile ─────────────────────────────────────────────────────────────────

class _TodoTile extends StatelessWidget {
  final TodoItem todo;
  final String coupleId;
  final FirestoreService firestore;
  final VoidCallback onTap;

  const _TodoTile({
    required this.todo,
    required this.coupleId,
    required this.firestore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(todo.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      onDismissed: (_) => firestore.deleteTodo(coupleId, todo.id),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: GestureDetector(
              onTap: () => firestore.toggleTodo(coupleId, todo),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
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
                    ? const Icon(Icons.check, color: Colors.white, size: 15)
                    : null,
              ),
            ),
            title: Text(
              todo.title,
              style: TextStyle(
                decoration: todo.isDone ? TextDecoration.lineThrough : null,
                color: todo.isDone ? AppTheme.textMuted : AppTheme.textDark,
                fontSize: 15,
              ),
            ),
            trailing: StreamBuilder<List<TodoComment>>(
              stream: firestore.commentStream(coupleId, todo.id),
              builder: (context, snap) {
                final count = snap.data?.length ?? 0;
                if (count == 0) {
                  return const Icon(Icons.chevron_right,
                      color: AppTheme.textMuted, size: 20);
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.comment_outlined,
                        size: 14, color: AppTheme.textMuted),
                    const SizedBox(width: 3),
                    Text('$count',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textMuted)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        color: AppTheme.textMuted, size: 20),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Todo detail bottom sheet ──────────────────────────────────────────────────

class _TodoDetailSheet extends StatefulWidget {
  final TodoItem todo;
  final String coupleId;
  final FirestoreService firestore;
  final String myName;

  const _TodoDetailSheet({
    required this.todo,
    required this.coupleId,
    required this.firestore,
    required this.myName,
  });

  @override
  State<_TodoDetailSheet> createState() => _TodoDetailSheetState();
}

class _TodoDetailSheetState extends State<_TodoDetailSheet> {
  final _commentCtrl = TextEditingController();
  bool _sending = false;

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    _commentCtrl.clear();
    await widget.firestore.addComment(
      widget.coupleId,
      widget.todo.id,
      TodoComment(
        id: const Uuid().v4(),
        text: text,
        authorName: widget.myName,
        createdAt: DateTime.now(),
      ),
    );
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scrollCtrl) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => widget.firestore
                      .toggleTodo(widget.coupleId, widget.todo),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(top: 2),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: widget.todo.isDone
                          ? AppTheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: widget.todo.isDone
                            ? AppTheme.primary
                            : AppTheme.textMuted,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: widget.todo.isDone
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 15)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.todo.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                      decoration: widget.todo.isDone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.divider, height: 1),
          // Comments list
          Expanded(
            child: StreamBuilder<List<TodoComment>>(
              stream:
                  widget.firestore.commentStream(widget.coupleId, widget.todo.id),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final comments = snap.data!;
                if (comments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            size: 36, color: AppTheme.textMuted),
                        const SizedBox(height: 10),
                        Text('No notes yet',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 14)),
                        Text('Add a note below',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 13)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: comments.length,
                  itemBuilder: (ctx, i) {
                    final c = comments[i];
                    final isMe = c.authorName == widget.myName;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (!isMe) ...[
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.primaryLight,
                              child: Text(
                                c.authorName[0],
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? AppTheme.primary
                                    : AppTheme.surface,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft:
                                      Radius.circular(isMe ? 16 : 4),
                                  bottomRight:
                                      Radius.circular(isMe ? 4 : 16),
                                ),
                                border: isMe
                                    ? null
                                    : Border.all(color: AppTheme.divider),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe)
                                    Text(c.authorName,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isMe
                                                ? Colors.white70
                                                : AppTheme.primary)),
                                  Text(c.text,
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: isMe
                                              ? Colors.white
                                              : AppTheme.textDark)),
                                  const SizedBox(height: 2),
                                  Text(
                                    timeago.format(c.createdAt,
                                        locale: 'en_short'),
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: isMe
                                            ? Colors.white54
                                            : AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isMe) const SizedBox(width: 8),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Comment input
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(top: BorderSide(color: AppTheme.divider)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Add a note...',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sending ? null : _sendComment,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
