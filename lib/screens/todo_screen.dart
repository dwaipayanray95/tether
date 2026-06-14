import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/todo_model.dart';
import '../models/comment_model.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/log_service.dart';
import '../theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
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
  bool _showDone = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _showAddDialog() {
    _titleCtrl.clear();
    _detailsCtrl.clear();
    DateTime? selectedDueDate;
    String? selectedPriority;
    String? selectedAssignedTo;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> pickDueDateTime() async {
            final date = await showDatePicker(
              context: context,
              initialDate: selectedDueDate ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              builder: (context, child) => Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppTheme.primary,
                    onPrimary: Colors.white,
                    onSurface: AppTheme.textDark,
                  ),
                ),
                child: child!,
              ),
            );
            if (date == null) return;

            if (!context.mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(selectedDueDate ?? DateTime.now()),
              builder: (context, child) => Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppTheme.primary,
                    onPrimary: Colors.white,
                    onSurface: AppTheme.textDark,
                  ),
                ),
                child: child!,
              ),
            );
            if (time == null) return;

            setState(() {
              selectedDueDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
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
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Add details (optional)',
                      alignLabelWithHint: true,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),

                  // Assignee Selector
                  Text('Assign to',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textMuted, letterSpacing: 0.3)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildChipOption(
                        label: 'Unassigned',
                        selected: selectedAssignedTo == null,
                        onTap: () => setState(() => selectedAssignedTo = null),
                      ),
                      const SizedBox(width: 8),
                      _buildChipOption(
                        label: 'Both',
                        selected: selectedAssignedTo == 'both',
                        onTap: () => setState(() => selectedAssignedTo = 'both'),
                      ),
                      const SizedBox(width: 8),
                      _buildChipOption(
                        label: 'Raayyy',
                        selected: selectedAssignedTo == 'ray',
                        onTap: () => setState(() => selectedAssignedTo = 'ray'),
                      ),
                      const SizedBox(width: 8),
                      _buildChipOption(
                        label: 'Aproo',
                        selected: selectedAssignedTo == 'aproo',
                        onTap: () => setState(() => selectedAssignedTo = 'aproo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Priority Selector
                  Text('Priority',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textMuted, letterSpacing: 0.3)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildChipOption(
                        label: 'None',
                        selected: selectedPriority == null,
                        onTap: () => setState(() => selectedPriority = null),
                      ),
                      const SizedBox(width: 8),
                      _buildChipOption(
                        label: 'Low',
                        selected: selectedPriority == 'low',
                        color: Colors.blue.shade100,
                        selectedColor: Colors.blue.shade600,
                        onTap: () => setState(() => selectedPriority = 'low'),
                      ),
                      const SizedBox(width: 8),
                      _buildChipOption(
                        label: 'Medium',
                        selected: selectedPriority == 'medium',
                        color: Colors.amber.shade100,
                        selectedColor: Colors.amber.shade700,
                        onTap: () => setState(() => selectedPriority = 'medium'),
                      ),
                      const SizedBox(width: 8),
                      _buildChipOption(
                        label: 'High',
                        selected: selectedPriority == 'high',
                        color: AppTheme.primaryLight,
                        selectedColor: AppTheme.primary,
                        onTap: () => setState(() => selectedPriority = 'high'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Due Date & Time Picker
                  Text('Due Date & Time',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textMuted, letterSpacing: 0.3)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: pickDueDateTime,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.divider),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                            color: selectedDueDate != null ? AppTheme.primary : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedDueDate != null
                                  ? DateFormat('MMM d, yyyy  ·  h:mm a').format(selectedDueDate!)
                                  : 'No due date set',
                              style: TextStyle(
                                fontSize: 14,
                                color: selectedDueDate != null ? AppTheme.textDark : AppTheme.textMuted,
                                fontWeight: selectedDueDate != null ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (selectedDueDate != null)
                            GestureDetector(
                              onTap: () => setState(() => selectedDueDate = null),
                              child: const Icon(Icons.close, size: 18, color: AppTheme.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final title = _titleCtrl.text.trim();
                        if (title.isEmpty) return;
                        final details = _detailsCtrl.text.trim();
                        _add(
                          title: title,
                          details: details,
                          dueDate: selectedDueDate,
                          assignedTo: selectedAssignedTo,
                          priority: selectedPriority,
                        );
                        Navigator.pop(ctx);
                      },
                      child: const Text('Add Task'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChipOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
    Color? selectedColor,
  }) {
    final isDefault = color == null;
    final bg = selected
        ? (selectedColor ?? AppTheme.primary)
        : (isDefault ? Colors.transparent : color.withAlpha(76)); // 0.3 * 255
    final fg = selected
        ? Colors.white
        : (isDefault ? AppTheme.textDark : (selectedColor ?? AppTheme.primary));
    final border = selected
        ? Border.all(color: Colors.transparent)
        : Border.all(color: isDefault ? AppTheme.divider : color.withAlpha(127)); // 0.5 * 255

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Future<void> _add({
    required String title,
    required String details,
    DateTime? dueDate,
    String? assignedTo,
    String? priority,
  }) async {
    LogService.log('Adding new to-do: $title');
    HapticFeedback.mediumImpact();
    await _firestore.addTodo(
      _coupleId,
      TodoItem(
        id: const Uuid().v4(),
        title: title,
        details: details.isEmpty ? null : details,
        isDone: false,
        createdBy: _myUid,
        createdAt: DateTime.now(),
        dueDate: dueDate,
        assignedTo: assignedTo,
        priority: priority,
      ),
    );
    final myKey = _auth.isRay ? 'ray' : 'aproo';
    await _firestore.updatePresence(myKey);
  }

  void _openDetail(TodoItem todo) {
    LogService.log('Opening to-do details: ${todo.title}');
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NotificationService.syncTodoNotifications(todos);
          });
          final pending = todos.where((t) => !t.isDone).toList();
          final done = todos.where((t) => t.isDone).toList();
          done.sort((a, b) {
            final timeA = a.completedAt ?? a.createdAt;
            final timeB = b.completedAt ?? b.createdAt;
            return timeB.compareTo(timeA); // Most recent completed tasks at the top
          });

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
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (int i = 0; i < pending.length; i++) ...[
                        _TodoTile(
                          todo: pending[i],
                          coupleId: _coupleId,
                          firestore: _firestore,
                          onTap: () => _openDetail(pending[i]),
                          isStacked: true,
                        ),
                        if (i < pending.length - 1)
                          const Divider(
                            color: AppTheme.divider,
                            height: 1,
                            indent: 56,
                          ),
                      ],
                    ],
                  ),
                ),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 24),
                InkWell(
                  onTap: () => setState(() => _showDone = !_showDone),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'DONE',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: AppTheme.textMuted,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.divider,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${done.length}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textMuted,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          _showDone ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: AppTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_showDone)
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface.withAlpha(200),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (int i = 0; i < done.length; i++) ...[
                          _TodoTile(
                            todo: done[i],
                            coupleId: _coupleId,
                            firestore: _firestore,
                            onTap: () => _openDetail(done[i]),
                            isStacked: true,
                          ),
                          if (i < done.length - 1)
                            const Divider(
                              color: AppTheme.divider,
                              height: 1,
                              indent: 56,
                            ),
                        ],
                      ],
                    ),
                  ),
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
  final bool isStacked;

  const _TodoTile({
    required this.todo,
    required this.coupleId,
    required this.firestore,
    required this.onTap,
    this.isStacked = false,
  });

  Widget _buildPriorityIndicator(String priority) {
    Color color;
    String label;
    switch (priority) {
      case 'high':
        color = AppTheme.primary;
        label = 'High';
        break;
      case 'medium':
        color = Colors.amber.shade700;
        label = 'Medium';
        break;
      case 'low':
        color = Colors.blue.shade600;
        label = 'Low';
        break;
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30), // 0.12 * 255
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDueDateIndicator(DateTime dueDate, bool isDone) {
    final isOverdue = !isDone && dueDate.isBefore(DateTime.now());
    final color = isOverdue ? AppTheme.primary : AppTheme.textMuted;
    final bg = isOverdue ? AppTheme.primaryLight : AppTheme.divider;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_filled_rounded, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            DateFormat('MMM d, h:mm a').format(dueDate),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssigneeIndicator(String? assignedTo) {
    if (assignedTo == null) {
      return const SizedBox.shrink();
    }
    final label = assignedTo == 'both'
        ? 'Both'
        : (assignedTo == 'ray' ? 'Raayyy' : 'Aproo');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '👤 $label',
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildChecklistProgress(List<ChecklistItem> checklist) {
    if (checklist.isEmpty) return const SizedBox.shrink();
    final doneCount = checklist.where((item) => item.isDone).length;
    final total = checklist.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_box_outlined, size: 10, color: AppTheme.primary),
          const SizedBox(width: 4),
          Text(
            '$doneCount/$total',
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTodo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task?'),
        content: Text('Are you sure you want to permanently delete "${todo.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(ctx);
              NotificationService.cancelTodoReminder(todo.id);
              firestore.deleteTodo(coupleId, todo.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final swipeColor = todo.isDone ? Colors.amber.shade50 : Colors.green.shade50;
    final swipeIcon = todo.isDone ? Icons.undo_rounded : Icons.check_circle_outline_rounded;
    final swipeIconColor = todo.isDone ? Colors.amber.shade800 : Colors.green.shade600;

    final swipeBackground = Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      decoration: BoxDecoration(
        color: swipeColor,
        borderRadius: isStacked ? BorderRadius.zero : BorderRadius.circular(14),
      ),
      child: Icon(swipeIcon, color: swipeIconColor),
    );

    final swipeSecondaryBackground = Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: swipeColor,
        borderRadius: isStacked ? BorderRadius.zero : BorderRadius.circular(14),
      ),
      child: Icon(swipeIcon, color: swipeIconColor),
    );

    return Dismissible(
      key: Key(todo.id),
      direction: DismissDirection.horizontal,
      background: swipeBackground,
      secondaryBackground: swipeSecondaryBackground,
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        await firestore.toggleTodo(coupleId, todo);
        return false; // Prevents the tile from disappearing, triggers beautiful slide-back
      },
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () {
          HapticFeedback.heavyImpact();
          _confirmDeleteTodo(context);
        },
        child: Container(
          margin: isStacked ? EdgeInsets.zero : const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isStacked ? Colors.transparent : AppTheme.surface,
            borderRadius: isStacked ? BorderRadius.zero : BorderRadius.circular(14),
            border: isStacked ? null : Border.all(color: AppTheme.divider),
          ),
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: GestureDetector(
              onTap: () {
                if (todo.isDone) {
                  HapticFeedback.lightImpact();
                } else {
                  HapticFeedback.mediumImpact();
                }
                firestore.toggleTodo(coupleId, todo);
              },
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
            subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (todo.details != null && todo.details!.isNotEmpty) ...[
                          Text(
                            todo.details!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (todo.priority != null)
                              _buildPriorityIndicator(todo.priority!),
                            if (todo.dueDate != null)
                              _buildDueDateIndicator(todo.dueDate!, todo.isDone),
                            _buildAssigneeIndicator(todo.assignedTo),
                            if (todo.checklist.isNotEmpty)
                              _buildChecklistProgress(todo.checklist),
                          ],
                        ),
                      ],
                    ),
                  ),
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
  final _subtaskCtrl = TextEditingController();
  bool _sending = false;
  bool _editingDetails = false;

  @override
  void initState() {
    super.initState();
    _detailsCtrl.text = widget.todo.details ?? '';
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _detailsCtrl.dispose();
    _subtaskCtrl.dispose();
    super.dispose();
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
      widget.todo.title,
    );
    HapticFeedback.lightImpact();
    final myKey = widget.myName == 'Ray' ? 'ray' : 'aproo';
    await widget.firestore.updatePresence(myKey);
    if (mounted) setState(() => _sending = false);
  }

  void _confirmDeleteComment(String commentId, String authorName) {
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
              HapticFeedback.mediumImpact();
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

  Future<void> _pickDueDate(TodoItem currentTodo) async {
    final date = await showDatePicker(
      context: context,
      initialDate: currentTodo.dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
            onPrimary: Colors.white,
            onSurface: AppTheme.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentTodo.dueDate ?? DateTime.now()),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
            onPrimary: Colors.white,
            onSurface: AppTheme.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    final newDueDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    HapticFeedback.lightImpact();
    await widget.firestore.updateTodoMetadata(
      widget.coupleId,
      todoId: currentTodo.id,
      dueDate: newDueDate,
    );
  }

  Widget _buildChecklistSection(TodoItem todo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sub-tasks',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textMuted, letterSpacing: 0.3),
              ),
              if (todo.checklist.isNotEmpty)
                Text(
                  '${todo.checklist.where((i) => i.isDone).length}/${todo.checklist.length}',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        if (todo.checklist.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: todo.checklist.length,
            itemBuilder: (context, index) {
              final item = todo.checklist[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        final updated = todo.checklist.map((c) {
                          if (c.id == item.id) {
                            return c.copyWith(isDone: !c.isDone);
                          }
                          return c;
                        }).toList();
                        widget.firestore.updateTodoChecklist(
                          widget.coupleId,
                          todo.id,
                          updated,
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: item.isDone ? AppTheme.primary : Colors.transparent,
                          border: Border.all(
                            color: item.isDone ? AppTheme.primary : AppTheme.textMuted,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: item.isDone
                            ? const Icon(Icons.check, color: Colors.white, size: 12)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 14,
                          color: item.isDone ? AppTheme.textMuted : AppTheme.textDark,
                          decoration: item.isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textMuted),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        final updated = todo.checklist.where((c) => c.id != item.id).toList();
                        widget.firestore.updateTodoChecklist(
                          widget.coupleId,
                          todo.id,
                          updated,
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _subtaskCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Add sub-task...',
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 13),
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _addSubtask(todo),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primary, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _addSubtask(todo),
              ),
            ],
          ),
        ),
        const Divider(color: AppTheme.divider, height: 1),
      ],
    );
  }

  void _addSubtask(TodoItem todo) {
    final title = _subtaskCtrl.text.trim();
    if (title.isEmpty) return;
    HapticFeedback.lightImpact();
    final newItem = ChecklistItem(
      id: const Uuid().v4(),
      title: title,
      isDone: false,
    );
    final updated = [...todo.checklist, newItem];
    widget.firestore.updateTodoChecklist(widget.coupleId, todo.id, updated);
    _subtaskCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, scrollCtrl) => StreamBuilder<TodoItem>(
        stream: widget.firestore.todoDocStream(widget.coupleId, widget.todo.id),
        initialData: widget.todo,
        builder: (context, snapshot) {
          final currentTodo = snapshot.data ?? widget.todo;
          return Column(
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
                          widget.firestore.toggleTodo(widget.coupleId, currentTodo),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(top: 3),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: currentTodo.isDone
                              ? AppTheme.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: currentTodo.isDone
                                ? AppTheme.primary
                                : AppTheme.textMuted,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: currentTodo.isDone
                            ? const Icon(Icons.check, color: Colors.white, size: 15)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        currentTodo.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                          decoration: currentTodo.isDone
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
                              onPressed: () async {
                                final details = _detailsCtrl.text.trim();
                                await widget.firestore.updateTodoDetails(
                                    widget.coupleId, currentTodo.id, details);
                                if (mounted) setState(() => _editingDetails = false);
                              },
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
                                currentTodo.details?.isNotEmpty == true
                                    ? currentTodo.details!
                                    : 'Add details...',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: currentTodo.details?.isNotEmpty == true
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

              // Metadata Row (Assignee, Priority, Alarm/Due Date)
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 4, 20, 16),
                child: Column(
                  children: [
                    // Assignee row
                    Row(
                      children: [
                        const Icon(Icons.person_rounded, size: 16, color: AppTheme.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Assignee:',
                            style: GoogleFonts.dmSans(fontSize: 13, color: AppTheme.textMuted),
                          ),
                        ),
                        PopupMenuButton<String?>(
                          initialValue: currentTodo.assignedTo,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              currentTodo.assignedTo == null
                                  ? 'Unassigned'
                                  : currentTodo.assignedTo == 'both'
                                      ? 'Both'
                                      : currentTodo.assignedTo == 'ray'
                                          ? 'Raayyy'
                                          : 'Aproo',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          onSelected: (val) async {
                            HapticFeedback.lightImpact();
                            await widget.firestore.updateTodoMetadata(
                              widget.coupleId,
                              todoId: currentTodo.id,
                              assignedTo: val,
                            );
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: null,
                              child: Text('Unassigned'),
                            ),
                            const PopupMenuItem(
                              value: 'both',
                              child: Text('Both'),
                            ),
                            const PopupMenuItem(
                              value: 'ray',
                              child: Text('Raayyy'),
                            ),
                            const PopupMenuItem(
                              value: 'aproo',
                              child: Text('Aproo'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Priority row
                    Row(
                      children: [
                        const Icon(Icons.outlined_flag_rounded, size: 16, color: AppTheme.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Priority:',
                            style: GoogleFonts.dmSans(fontSize: 13, color: AppTheme.textMuted),
                          ),
                        ),
                        PopupMenuButton<String?>(
                          initialValue: currentTodo.priority,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: currentTodo.priority == 'high'
                                  ? Colors.red.shade50
                                  : currentTodo.priority == 'medium'
                                      ? Colors.amber.shade50
                                      : currentTodo.priority == 'low'
                                          ? Colors.blue.shade50
                                          : AppTheme.background,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              currentTodo.priority == null
                                  ? 'None'
                                  : currentTodo.priority![0].toUpperCase() + currentTodo.priority!.substring(1),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: currentTodo.priority == 'high'
                                    ? Colors.red.shade700
                                    : currentTodo.priority == 'medium'
                                        ? Colors.amber.shade800
                                        : currentTodo.priority == 'low'
                                            ? Colors.blue.shade700
                                            : AppTheme.textMuted,
                              ),
                            ),
                          ),
                          onSelected: (val) async {
                            HapticFeedback.lightImpact();
                            await widget.firestore.updateTodoMetadata(
                              widget.coupleId,
                              todoId: currentTodo.id,
                              priority: val,
                            );
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: null,
                              child: Text('None'),
                            ),
                            const PopupMenuItem(
                              value: 'low',
                              child: Text('Low'),
                            ),
                            const PopupMenuItem(
                              value: 'medium',
                              child: Text('Medium'),
                            ),
                            const PopupMenuItem(
                              value: 'high',
                              child: Text('High'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Alarm / Due Date row
                    Row(
                      children: [
                        const Icon(Icons.alarm_rounded, size: 16, color: AppTheme.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Due Alert:',
                            style: GoogleFonts.dmSans(fontSize: 13, color: AppTheme.textMuted),
                          ),
                        ),
                        if (currentTodo.dueDate != null) ...[
                          GestureDetector(
                            onTap: () => _pickDueDate(currentTodo),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                DateFormat('MMM d, h:mm a').format(currentTodo.dueDate!),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.purple.shade700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.redAccent),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () async {
                              HapticFeedback.mediumImpact();
                              await widget.firestore.updateTodoMetadata(
                                widget.coupleId,
                                todoId: currentTodo.id,
                                clearDueDate: true,
                              );
                            },
                          ),
                        ] else
                          GestureDetector(
                            onTap: () => _pickDueDate(currentTodo),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Set Alert',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(color: AppTheme.divider, height: 1),

              // Checklist Section
              _buildChecklistSection(currentTodo),

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
                      .commentStream(widget.coupleId, currentTodo.id),
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
                          onLongPress: () => _confirmDeleteComment(c.id, c.authorName),
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
                                if (isMe) ...[
                                  GestureDetector(
                                    onTap: () => _confirmDeleteComment(c.id, c.authorName),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      child: Icon(Icons.more_vert,
                                          size: 16, color: AppTheme.textMuted),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? AppTheme.primary
                                          : AppTheme.surface,
                                      borderRadius: isMe
                                          ? const BorderRadius.only(
                                              topLeft: Radius.circular(16),
                                              topRight: Radius.circular(16),
                                              bottomLeft: Radius.circular(16),
                                              bottomRight: Radius.circular(4),
                                            )
                                          : const BorderRadius.only(
                                              topLeft: Radius.circular(16),
                                              topRight: Radius.circular(16),
                                              bottomLeft: Radius.circular(4),
                                              bottomRight: Radius.circular(16),
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
                                if (!isMe) ...[
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => _confirmDeleteComment(c.id, c.authorName),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                      child: Icon(Icons.more_vert,
                                          size: 16, color: AppTheme.textMuted),
                                    ),
                                  ),
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
          );
        },
      ),
    );
  }
}
