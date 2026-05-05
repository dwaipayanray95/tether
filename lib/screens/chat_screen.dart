import 'dart:async';
import 'dart:math' show max;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:uuid/uuid.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';
import '../models/message_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'call_screen.dart';

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
  final _auth = AuthService();
  final _textCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  static const String _coupleId = coupleId;

  // Scroll
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();

  // Pagination state
  List<Message> _messages = [];
  DocumentSnapshot? _pageCursor;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _initialLoading = true;
  StreamSubscription<List<Message>>? _streamSub;

  // Highlight
  String? _highlightedId;

  // Reply
  Message? _replyTo;

  // Search
  bool _searchActive = false;
  String _searchQuery = '';
  List<Message>? _allMessages; // null = not yet loaded
  bool _loadingAllMessages = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get isSearchActive => _searchActive;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    NotificationService.chatIsOpen = true;
    _loadInitialMessages();
    _itemPositionsListener.itemPositions.addListener(_onPositionsChanged);
  }

  @override
  void dispose() {
    NotificationService.chatIsOpen = false;
    _streamSub?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onPositionsChanged);
    _textCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<void> _loadInitialMessages() async {
    final result = await _firestore.fetchMessagePage(_coupleId, 50);
    if (!mounted) return;
    setState(() {
      _messages = result.messages;
      _pageCursor = result.cursor;
      _hasMore = result.messages.length == 50;
      _initialLoading = false;
    });
    _firestore.markMessagesRead(_coupleId, _myUid);

    // Real-time stream for new messages + live updates (reactions, readBy)
    _streamSub = _firestore.messageStream(_coupleId).listen(_onStreamUpdate);
  }

  void _onStreamUpdate(List<Message> streamMessages) {
    if (!mounted) return;
    setState(() {
      final existingIds = {for (final m in _messages) m.id};
      // Prepend any genuinely new messages (not yet in our list)
      final newOnes = streamMessages
          .where((m) => !existingIds.contains(m.id))
          .toList();
      // Update existing messages in-place (reactions, readBy, etc.)
      final streamMap = {for (final m in streamMessages) m.id: m};
      final updated = _messages.map((m) => streamMap[m.id] ?? m).toList();
      _messages = [...newOnes, ...updated];
    });
    _firestore.markMessagesRead(_coupleId, _myUid);
  }

  void _onPositionsChanged() {
    if (_isLoadingMore || !_hasMore || _messages.isEmpty) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final maxIdx = positions.map((p) => p.index).reduce(max);
    // In reversed list index 0 is newest; high index = oldest.
    // Load more when user is near the oldest loaded message.
    if (maxIdx >= _messages.length - 10) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore || _pageCursor == null) return;
    setState(() => _isLoadingMore = true);
    final result = await _firestore.fetchMessagePage(
      _coupleId,
      50,
      startAfter: _pageCursor,
    );
    if (!mounted) return;
    setState(() {
      final existingIds = {for (final m in _messages) m.id};
      final newOnes =
          result.messages.where((m) => !existingIds.contains(m.id)).toList();
      _messages = [..._messages, ...newOnes];
      _pageCursor = result.cursor;
      _hasMore = result.messages.length == 50;
      _isLoadingMore = false;
    });
  }

  // ── Public API (called by MainShell / SearchScreen) ──────────────────────────

  /// Scroll to the message with [id] and briefly highlight it.
  void scrollToMessageById(String id) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    _itemScrollController.scrollTo(
      index: idx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() => _highlightedId = id);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  void closeSearch() {
    if (mounted) {
      setState(() {
        _searchActive = false;
        _searchQuery = '';
        _searchCtrl.clear();
      });
    }
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

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
                          child: Text(e, style: const TextStyle(fontSize: 28)),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _startCall() {
    LogService.log('Outgoing CALL initiated by user');
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(
        isOutgoing: true,
        partnerName: _auth.partnerName,
      ),
    ));
  }

  Future<void> _activateSearch() async {
    LogService.log('Chat SEARCH activated');
    setState(() => _searchActive = true);
    // Eagerly load full message history for search
    if (_allMessages == null && !_loadingAllMessages) {
      LogService.log('Fetching ALL messages for search index');
      setState(() => _loadingAllMessages = true);
      final all = await _firestore.getAllMessages(_coupleId);
      if (mounted) {
        setState(() {
          _allMessages = all;
          _loadingAllMessages = false;
        });
        LogService.log('Search index ready: ${all.length} messages');
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  List<Message> get _displayMessages {
    if (_searchQuery.isEmpty) return _messages;
    final source = _allMessages ?? _messages;
    final q = _searchQuery.toLowerCase();
    return source.where((m) => m.text.toLowerCase().contains(q)).toList();
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
                  hintText: 'Search all messages…',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: AppTheme.textMuted),
                ),
                style: const TextStyle(fontSize: 16),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              )
            : const Text('Raayyy & Aproo'),
        actions: [
          if (_searchActive)
            _loadingAllMessages
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
          else ...[
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: _activateSearch,
            ),
            IconButton(
              icon: const Icon(Icons.call_rounded),
              onPressed: _startCall,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          if (!_searchActive) _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final display = _displayMessages;

    if (_messages.isEmpty) {
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

    if (display.isEmpty && _searchQuery.isNotEmpty) {
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

    // +1 slot at the end (top of screen) for load-more indicator
    final itemCount = display.length + (_isLoadingMore ? 1 : 0);

    return ScrollablePositionedList.builder(
      reverse: true,
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        if (i == display.length) {
          // Load-more spinner at the visual top (oldest end)
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final msg = display[i];
        return AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          color: msg.id == _highlightedId
              ? AppTheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          child: _SwipeableMessage(
            isMe: msg.senderId == _myUid,
            onReply: () => _setReply(msg),
            child: _MessageBubble(
              message: msg,
              isMe: msg.senderId == _myUid,
              showReceipt: i == 0 && msg.senderId == _myUid,
              myUid: _myUid,
              onLongPress: () => _showReactionPicker(msg),
              onReaction: (emoji) => _toggleReaction(msg.id, emoji),
              onReplyTap: msg.replyToId != null
                  ? () => scrollToMessageById(msg.replyToId!)
                  : null,
              searchQuery: _searchQuery,
            ),
          ),
        );
      },
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
                      minLines: 1,
                      maxLines: 6,
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
  final VoidCallback? onReplyTap;
  final String searchQuery;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showReceipt,
    required this.myUid,
    required this.onLongPress,
    required this.onReaction,
    this.onReplyTap,
    this.searchQuery = '',
  });

  Widget _buildMessageText(String text, bool isMe) {
    final baseColor = isMe ? Colors.white : AppTheme.textDark;
    if (searchQuery.isEmpty) {
      return Text(text, style: TextStyle(color: baseColor, fontSize: 15));
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
                        maxWidth: MediaQuery.of(context).size.width * 0.72),
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
                      border:
                          isMe ? null : Border.all(color: AppTheme.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Reply preview — tappable to scroll to original
                        if (message.replyToText != null)
                          GestureDetector(
                            onTap: onReplyTap,
                            child: Container(
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
                        color:
                            isRead ? AppTheme.primary : AppTheme.textMuted,
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
