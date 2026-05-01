import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/todo_model.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final _firestore = FirestoreService();
  final _textCtrl = TextEditingController();
  static const String _coupleId = 'ray-aproo';

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
            Text('Add to list',
                style: Theme.of(context).textTheme.titleMedium),
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
              child: ElevatedButton(
                onPressed: _add,
                child: const Text('Add'),
              ),
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
            padding: const EdgeInsets.all(20),
            children: [
              if (pending.isNotEmpty) ...[
                _sectionLabel('To do'),
                const SizedBox(height: 8),
                ...pending.map((t) => _TodoTile(
                      todo: t,
                      coupleId: _coupleId,
                      firestore: _firestore,
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

class _TodoTile extends StatelessWidget {
  final TodoItem todo;
  final String coupleId;
  final FirestoreService firestore;

  const _TodoTile(
      {required this.todo,
      required this.coupleId,
      required this.firestore});

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
              decoration:
                  todo.isDone ? TextDecoration.lineThrough : null,
              color: todo.isDone ? AppTheme.textMuted : AppTheme.textDark,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
