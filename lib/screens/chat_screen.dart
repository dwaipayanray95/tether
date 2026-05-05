import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';
import '../models/message_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

const _reactionEmojis = [
  '❤️', '😂', '😍', '👍', '💃', '🥳',
  '🔥', '😘', '🥰', '💕', '✨', '🎉',
  '😁', '🤩', '💯', '🙈', '🫶', '🥹',
];

class ChatScreen extends StatefulWidget {
  final void Function(int)? onNavigate;

  const ChatScreen({super.key, this.onNavigate});

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final _firestore = FirestoreService();
  bool get isSearchActive => _searchActive;

  void closeSearch() {
    if (mounted) {
      setState(() {
        _searchActive = false;
        _searchQuery = '';
        _searchCtrl.clear();
      });
    }
  }

  final _scrollCtrl = ScrollController();
  final _auth = AuthService();
  final _textCtrl = TextEditingController();
  static const String _coupleId = coupleId;

  Message? _replyTo;

  // Search
  bool _searchActive = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    NotificationService.chatIsOpen = true;
    _firestore.markMessagesRead(_coupleId, _myUid);
  }

  @override
  void dispose() {
    NotificationService.chatIsOpen = false;
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setReply(Message message) {
    HapticFeedback.lightImpact();
    setState(() => _replyTo = message);
  }

  void _clearReply() => setState(() => _replyTo = null);

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    final reply = _replyTo;
    _textCtrl.clear();
    _clearReply();
    await _firestore.sendMessage(
      _coupleId,
      Message(
        id: const Uuid().v4(),
        senderId: _myUid,
        text: text,
        type: MessageType.text,
        sentAt: DateTime.now(),
        readBy: [_myUid],
        replyToId: reply?.id,
        replyToText: reply?.text,
      ),
      senderName: _auth.myName,
    );
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    await _firestore.toggleReaction(_coupleId, messageId, emoji, _myUid);
  }

  void _showReactionPicker(Message message) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('React', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 4,
              children: _reactionEmojis
                  .map((e) => GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _toggleReaction(message.id, e);
                        },
                        child: Center(
                          child: Text(e,
                              style: const TextStyle(fontSize: 28)),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: _searchActive ? false : null,
        leading: _searchActive
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: closeSearch,
              )
            : null,
        titleSpacing: _searchActive ? 0 : null,
        title: _searchActive
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search messages…',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: AppTheme.textMuted),
                ),
                style: const TextStyle(fontSize: 16),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              )
            : const Text('Raayyy & Aproo'),
        actions: [
          if (_searchActive)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _searchQuery = '');
              },
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => setState(() => _searchActive = true),
            ),
            Container(
              margin: const EdgeInsets.only(right: 16),
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _firestore.messageStream(_coupleId),
              builder: (context, snap) {
                if (snap.hasData) {
                  _firestore.markMessagesRead(_coupleId, _myUid);
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allMessages = snap.data!;
                final messages = _searchQuery.isEmpty
                    ? allMessages
                    : allMessages
                        .where((m) => m.text
                            .toLowerCase()
                            .contains(_searchQuery.toLowerCase()))
                        .toList();
                if (allMessages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            size: 48, color: AppTheme.textMuted),
                        const SizedBox(height: 12),
                        Text('Send your first message!',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppTheme.textMuted)),
                      ],
                    ),
                  );
                }
                if (messages.isEmpty && _searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off_rounded,
                            size: 48, color: AppTheme.textMuted),
                        const SizedBox(height: 12),
                        Text('No messages found for "$_searchQuery"',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppTheme.textMuted)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) => _SwipeableMessage(
                    isMe: messages[i].senderId == _myUid,
                    onReply: () => _setReply(messages[i]),
                    child: _MessageBubble(
                      message: messages[i],
                      isMe: messages[i].senderId == _myUid,
                      showReceipt: i == 0 && messages[i].senderId == _myUid,
                      myUid: _myUid,
                      onLongPress: () => _showReactionPicker(messages[i]),
                      onReaction: (emoji) =>
                          _toggleReaction(messages[i].id, emoji),
                      searchQuery: _searchQuery,
                    ),
                  ),
                );
              },
            ),
          ),
          if (!_searchActive) _buildInput(),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppTheme.primaryLight,
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _replyTo!.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textMuted),
                      ),
                    ),
                    GestureDetector(
                      onTap: _clearReply,
                      child: const Icon(Icons.close,
                          size: 16, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.image_outlined,
                        color: AppTheme.textMuted),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
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
          ],
        ),
      ),
    );
  }
}

// ── Swipeable wrapper ─────────────────────────────────────────────────────────

class _SwipeableMessage extends StatefulWidget {
  final Widget child;
  final bool isMe;
  final VoidCallback onReply;

  const _SwipeableMessage({
    required this.child,
    required this.isMe,
    required this.onReply,
  });

  @override
  State<_SwipeableMessage> createState() => _SwipeableMessageState();
}

class _SwipeableMessageState extends State<_SwipeableMessage> {
  double _offset = 0;
  bool _triggered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final delta = d.delta.dx;
        // Only allow right swipe (positive direction)
        if (delta > 0) {
          setState(() {
            _offset = (_offset + delta).clamp(0.0, 72.0);
          });
        }
      },
      onHorizontalDragEnd: (_) {
        if (_offset >= 56 && !_triggered) {
          _triggered = true;
          widget.onReply();
        }
        setState(() {
          _offset = 0;
          _triggered = false;
        });
      },
      child: Stack(
        children: [
          if (_offset > 8)
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: (_offset / 56).clamp(0.0, 1.0),
                  child: const Icon(Icons.reply_rounded,
                      color: AppTheme.primary, size: 20),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_offset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showReceipt;
  final String myUid;
  final VoidCallback onLongPress;
  final void Function(String emoji) onReaction;
  final String searchQuery;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showReceipt,
    required this.myUid,
    required this.onLongPress,
    required this.onReaction,
    this.searchQuery = '',
  });

  Widget _buildMessageText(String text, bool isMe) {
    final baseColor = isMe ? Colors.white : AppTheme.textDark;
    if (searchQuery.isEmpty) {
      return Text(text,
          style: TextStyle(color: baseColor, fontSize: 15));
    }
    final lower = text.toLowerCase();
    final queryLower = searchQuery.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int idx = lower.indexOf(queryLower);
    while (idx != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + searchQuery.length),
        style: TextStyle(
          backgroundColor:
              isMe ? Colors.white30 : AppTheme.primary.withValues(alpha: 0.25),
          fontWeight: FontWeight.w600,
        ),
      ));
      start = idx + searchQuery.length;
      idx = lower.indexOf(queryLower, start);
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return RichText(
      text: TextSpan(
          style: TextStyle(color: baseColor, fontSize: 15), children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRead = message.readBy.length > 1;
    final partnerReadTime = message.readTimes.entries
        .where((e) => e.key != myUid)
        .map((e) => e.value)
        .firstOrNull;
    final hasReactions = message.reactions.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 4),
              child: CircleAvatar(
                radius: 12,
                backgroundColor: AppTheme.primaryLight,
                child: const Text(
                  'A',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: onLongPress,
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(context).size.width * 0.72),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? AppTheme.primary : AppTheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                      border: isMe
                          ? null
                          : Border.all(color: AppTheme.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Reply preview
                        if (message.replyToText != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border(
                                left: BorderSide(
                                  color: isMe
                                      ? Colors.white
                                      : AppTheme.primary,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Text(
                              message.replyToText!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isMe
                                    ? Colors.white70
                                    : AppTheme.textMuted,
                              ),
                            ),
                          ),
                        _buildMessageText(message.text, isMe),
                      ],
                    ),
                  ),
                ),
                // Reactions
                if (hasReactions)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      children: message.reactions.entries.map((e) {
                        final reacted = e.value.contains(myUid);
                        return GestureDetector(
                          onTap: () => onReaction(e.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: reacted
                                  ? AppTheme.primaryLight
                                  : AppTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: reacted
                                    ? AppTheme.primary
                                    : AppTheme.divider,
                              ),
                            ),
                            child: Text(
                              '${e.key} ${e.value.length}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeago.format(message.sentAt, locale: 'en_short'),
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 10),
                    ),
                    if (isMe && showReceipt) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isRead
                            ? Icons.done_all_rounded
                            : Icons.done_rounded,
                        size: 14,
                        color: isRead
                            ? AppTheme.primary
                            : AppTheme.textMuted,
                      ),
                      if (isRead && partnerReadTime != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          'Read ${DateFormat.jm().format(partnerReadTime)}',
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 10),
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
