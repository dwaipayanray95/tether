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
  final _titleCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  static const String _coupleId = coupleId;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _showAddDialog() {
    _titleCtrl.clear();
    _detailsCtrl.clear();
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
              controller: _titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'What needs doing?'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _detailsCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Add details (optional)',
                alignLabelWithHint: true,
              ),
              textCapitalization: TextCapitalization.sentences,
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
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final details = _detailsCtrl.text.trim();
    Navigator.pop(context);
    await _firestore.addTodo(
      _coupleId,
      TodoItem(
        id: const Uuid().v4(),
        title: title,
        details: details.isEmpty ? null : details,
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
                    color: todo.isDone ? AppTheme.primary : AppTheme.textMuted,
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
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: todo.details != null && todo.details!.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      todo.details!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                    ),
                  )
                : null,
            trailing: StreamBuilder<List<TodoComment>>(
              stream: firestore.commentStream(coupleId, todo.id),
              builder: (context, snap) {
                final count = snap.data?.length ?? 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (count > 0) ...[
                      const Icon(Icons.comment_outlined,
                          size: 14, color: AppTheme.textMuted),
                      const SizedBox(width: 3),
                      Text('$count',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                      const SizedBox(width: 4),
                    ],
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
  final _detailsCtrl = TextEditingController();
  bool _sending = false;
  bool _editingDetails = false;

  @override
  void initState() {
    super.initState();
    _detailsCtrl.text = widget.todo.details ?? '';
  }

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

  Future<void> _saveDetails() async {
    final details = _detailsCtrl.text.trim();
    await widget.firestore.updateTodoDetails(
        widget.coupleId, widget.todo.id, details);
    if (mounted) setState(() => _editingDetails = false);
  }

  void _confirmDeleteComment(String commentId, String authorName) {
    if (authorName != widget.myName) return; // can only delete own comments
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This note will be removed permanently.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.firestore.deleteComment(
                  widget.coupleId, widget.todo.id, commentId);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
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

          // Title + checkbox
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () =>
                      widget.firestore.toggleTodo(widget.coupleId, widget.todo),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(top: 3),
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
                        ? const Icon(Icons.check, color: Colors.white, size: 15)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.todo.title,
                    style: TextStyle(
                      fontSize: 20,
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

          // Details section
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 10, 20, 12),
            child: _editingDetails
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _detailsCtrl,
                          autofocus: true,
                          maxLines: 4,
                          minLines: 1,
                          decoration: const InputDecoration(
                            hintText: 'Add details...',
                          ),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                          onPressed: _saveDetails,
                          child: const Text('Save',
                              style: TextStyle(color: AppTheme.primary))),
                    ],
                  )
                : GestureDetector(
                    onTap: () => setState(() => _editingDetails = true),
                    child: Row(
                      children: [
                        const Icon(Icons.notes_rounded,
                            size: 16, color: AppTheme.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.todo.details?.isNotEmpty == true
                                ? widget.todo.details!
                                : 'Add details...',
                            style: TextStyle(
                              fontSize: 14,
                              color: widget.todo.details?.isNotEmpty == true
                                  ? AppTheme.textDark
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ),
                        const Icon(Icons.edit_outlined,
                            size: 14, color: AppTheme.textMuted),
                      ],
                    ),
                  ),
          ),

          const Divider(color: AppTheme.divider, height: 1),

          // Notes header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text('Notes',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textMuted, letterSpacing: 0.3)),
          ),

          // Comments list
          Expanded(
            child: StreamBuilder<List<TodoComment>>(
              stream: widget.firestore
                  .commentStream(widget.coupleId, widget.todo.id),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final comments = snap.data!;
                if (comments.isEmpty) {
                  return Center(
                    child: Text('No notes yet — add one below',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 13)),
                  );
                }
                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  itemCount: comments.length,
                  itemBuilder: (ctx, i) {
                    final c = comments[i];
                    final isMe = c.authorName == widget.myName;
                    return GestureDetector(
                      onLongPress: isMe
                          ? () => _confirmDeleteComment(c.id, c.authorName)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: isMe
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            if (!isMe) ...[
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppTheme.primaryLight,
                                child: Text(c.authorName[0],
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w600)),
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
                                    Text(c.text,
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: isMe
                                                ? Colors.white
                                                : AppTheme.textDark)),
                                    const SizedBox(height: 3),
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
                            if (isMe) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.more_vert,
                                  size: 14, color: AppTheme.textMuted),
                            ],
                          ],
                        ),
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
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
