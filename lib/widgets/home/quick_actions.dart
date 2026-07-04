import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

class QuickActions extends StatelessWidget {
  final void Function(int) onNavigate;

  const QuickActions({
    super.key,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    const coupleId = 'ray-aproo';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick access',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textMuted, letterSpacing: 0.3)),
        const SizedBox(height: 12),
        Row(
          children: [
            _actionTile(
              context,
              Icons.check_circle_outline_rounded,
              'To-do',
              () => onNavigate(2),
            ),
            const SizedBox(width: 12),
            StreamBuilder<int>(
              stream: FirestoreService().unreadCountStream(coupleId, myUid),
              builder: (context, snap) {
                final unread = snap.data ?? 0;
                return _actionTile(
                  context,
                  Icons.chat_bubble_outline_rounded,
                  'Chat',
                  () => onNavigate(1),
                  unreadCount: unread,
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionTile(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? iconColor,
    Color? backgroundColor,
    int unreadCount = 0,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: backgroundColor ?? AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: backgroundColor != null
                  ? (iconColor ?? AppTheme.primary).withValues(alpha: 0.25)
                  : AppTheme.divider,
            ),
          ),
          child: Column(
            children: [
              Badge(
                isLabelVisible: unreadCount > 0,
                label: Text('$unreadCount'),
                backgroundColor: AppTheme.primary,
                child: Icon(icon, color: iconColor ?? AppTheme.primary, size: 24),
              ),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
