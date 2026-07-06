import 'dart:async';
import 'dart:math' show max;
import 'dart:io';
import 'dart:convert';
import '../services/crypto_service.dart';
import '../services/voice_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:uuid/uuid.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/message_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

const _reactionEmojis = [
  '❤️', '😂', '😍', '👍', '💃', '🥳',
  '🔥', '😘', '🥰', '💕', '✨', '🎉',
  '😁', '🤩', '💯', '🙈', '🫶', '🥹',
];

// ── Emoji Helpers ────────────────────────────────────────────────────────────

bool _isEmojiOnly(String text) {
  if (text.trim().isEmpty) return false;
  final regex = RegExp(
    r'^[\u{1f300}-\u{1f5ff}\u{1f900}-\u{1f9ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{2600}-\u{26ff}\u{2700}-\u{27bf}\u{1f1e6}-\u{1f1ff}\u{1f191}-\u{1f251}\u{1f004}\u{1f0cf}\u{1f170}-\u{1f171}\u{1f17e}-\u{1f17f}\u{1f18e}\u{3030}\u{2b50}\u{2b55}\u{2934}-\u{2935}\u{2b05}-\u{2b07}\u{2b1b}-\u{2b1c}\u{3297}\u{3299}\u{303d}\u{00a9}\u{00ae}\u{2122}\u{23f3}\u{24c2}\u{23e9}-\u{23ef}\u{25b6}\u{23f8}-\u{23fa}\u{200d}\u{fe0f}\s]+$',
    unicode: true,
  );
  return regex.hasMatch(text.trim());
}

int _countEmojis(String text) {
  final regex = RegExp(
    r'[\u{1f300}-\u{1f5ff}\u{1f900}-\u{1f9ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{2600}-\u{26ff}\u{2700}-\u{27bf}\u{1f1e6}-\u{1f1ff}\u{1f191}-\u{1f251}\u{1f004}\u{1f0cf}\u{1f170}-\u{1f171}\u{1f17e}-\u{1f17f}\u{1f18e}\u{3030}\u{2b50}\u{2b55}\u{2934}-\u{2935}\u{2b05}-\u{2b07}\u{2b1b}-\u{2b1c}\u{3297}\u{3299}\u{303d}\u{00a9}\u{00ae}\u{2122}\u{23f3}\u{24c2}\u{23e9}-\u{23ef}\u{25b6}\u{23f8}-\u{23fa}\u{200d}\u{fe0f}]',
    unicode: true,
  );
  return regex.allMatches(text).length;
}

class ChatScreen extends StatefulWidget {
  final bool isActive;
  final void Function(int)? onNavigate;

  const ChatScreen({super.key, required this.isActive, this.onNavigate});

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
  bool _showScrollToBottom = false;

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

  // Voice Recording state
  bool _isRecording = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  String? _recordingPath;
  bool _isSendingVoice = false;
  bool _isStoppingRecording = false;

  // E2EE decryption cache
  final Map<String, String> _decryptedTextCache = {};
  SecretKey? _sharedKey;

  Future<void> _initSharedKey() async {
    try {
      final partnerPubKey = await CryptoService().fetchPartnerPublicKey();
      if (partnerPubKey != null) {
        _sharedKey = await CryptoService().getSharedKey(partnerPubKey);
        if (mounted) setState(() {});
      }
    } catch (e) {
      LogService.log('Error pre-initializing shared key: $e');
    }
  }

  String _getOrDecryptText(Message message) {
    if (!message.text.startsWith('{"ciphertext":')) {
      return message.text;
    }
    if (_decryptedTextCache.containsKey(message.id)) {
      return _decryptedTextCache[message.id]!;
    }
    _decryptMessageInBackground(message);
    return '...';
  }

  Future<void> _decryptMessageInBackground(Message message) async {
    try {
      SecretKey? key = _sharedKey;
      if (key == null) {
        final partnerPubKey = await CryptoService().fetchPartnerPublicKey();
        if (partnerPubKey == null) {
          if (mounted) {
            setState(() {
              _decryptedTextCache[message.id] = message.text; // Fallback to raw text if no key found yet
            });
          }
          return;
        }
        key = await CryptoService().getSharedKey(partnerPubKey);
        _sharedKey = key;
      }
      final encryptedData = jsonDecode(message.text) as Map<String, dynamic>;
      final decrypted = await CryptoService().decryptText(encryptedData, key);
      if (mounted) {
        setState(() {
          _decryptedTextCache[message.id] = decrypted;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _decryptedTextCache[message.id] = '[Decryption failed: $e]';
        });
      }
    }
  }

  String? _getOrDecryptReplyText(Message message) {
    if (message.replyToText == null) return null;
    if (!message.replyToText!.startsWith('{"ciphertext":')) {
      return message.replyToText;
    }
    final replyId = message.replyToId;
    if (replyId == null) return '...';

    if (_decryptedTextCache.containsKey(replyId)) {
      return _decryptedTextCache[replyId]!;
    }

    final dummyReplyMsg = Message(
      id: replyId,
      senderId: '',
      text: message.replyToText!,
      type: MessageType.text,
      sentAt: DateTime.now(),
    );
    _decryptMessageInBackground(dummyReplyMsg);
    return '...';
  }

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
    NotificationService.chatIsOpen = widget.isActive;
    _loadInitialMessages();
    _initSharedKey();
    _itemPositionsListener.itemPositions.addListener(_onPositionsChanged);
    _textCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      NotificationService.chatIsOpen = widget.isActive;
      if (widget.isActive) {
        _firestore.markMessagesRead(_coupleId, _myUid);
      }
    }
  }

  @override
  void dispose() {
    NotificationService.chatIsOpen = false;
    _streamSub?.cancel();
    _recordingTimer?.cancel();
    VoiceService().disposeRecorder();
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
    if (widget.isActive) {
      _firestore.markMessagesRead(_coupleId, _myUid);
    }

    // Real-time stream for new messages + live updates (reactions, readBy)
    _streamSub = _firestore.messageStream(_coupleId).listen(_onStreamUpdate);
  }

  void _onStreamUpdate(List<Message> streamMessages) {
    if (!mounted) return;

    final existingIds = {for (final m in _messages) m.id};
    final newPartnerMessages = streamMessages
        .where((m) => !existingIds.contains(m.id) && m.senderId != _myUid)
        .toList();

    if (newPartnerMessages.isNotEmpty && !widget.isActive) {
      LogService.log('New incoming message received while chat tab is inactive. Triggering vibration.');
      HapticFeedback.vibrate();
    }

    setState(() {
      // Prepend any genuinely new messages (not yet in our list)
      final newOnes = streamMessages
          .where((m) => !existingIds.contains(m.id))
          .toList();
      // Update existing messages in-place (reactions, readBy, etc.)
      final streamMap = {for (final m in streamMessages) m.id: m};
      final updated = _messages.map((m) => streamMap[m.id] ?? m).toList();
      _messages = [...newOnes, ...updated];
    });
    if (widget.isActive) {
      _firestore.markMessagesRead(_coupleId, _myUid);
    }
  }

  void _onPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      final minIdx = positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
      // Show FAB if we're scrolled away from bottom (index 0)
      final show = minIdx > 1;
      if (show != _showScrollToBottom) {
        setState(() => _showScrollToBottom = show);
      }
    }

    if (_isLoadingMore || !_hasMore || _messages.isEmpty) return;
    if (positions.isEmpty) return;
    final maxIdx = positions.map((p) => p.index).reduce(max);
    // In reversed list index 0 is newest; high index = oldest.
    // Load more when user is near the oldest loaded message.
    if (maxIdx >= _messages.length - 10) {
      _loadMoreMessages();
    }
  }

  void _scrollToBottom() {
    _itemScrollController.scrollTo(
      index: 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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

    String textToSend = text;
    String? replyTextToSend = reply?.text;

    try {
      final partnerPubKey = await CryptoService().fetchPartnerPublicKey();
      if (partnerPubKey != null) {
        final sharedKey = await CryptoService().getSharedKey(partnerPubKey);
        final encryptedTextMap = await CryptoService().encryptText(text, sharedKey);
        textToSend = jsonEncode(encryptedTextMap);

        if (reply != null) {
          final plainReplyText = _getOrDecryptText(reply);
          final encryptedReplyMap = await CryptoService().encryptText(plainReplyText, sharedKey);
          replyTextToSend = jsonEncode(encryptedReplyMap);
        }
      }
    } catch (e) {
      LogService.log('Crypto Error: Encryption failed during send, falling back to plaintext: $e');
    }

    await _firestore.sendMessage(
      _coupleId,
      Message(
        id: const Uuid().v4(),
        senderId: _myUid,
        text: textToSend,
        type: MessageType.text,
        sentAt: DateTime.now(),
        readBy: [_myUid],
        replyToId: reply?.id,
        replyToText: replyTextToSend,
      ),
      senderName: _auth.myName,
    );
    final myKey = _auth.isRay ? 'ray' : 'aproo';
    await _firestore.updatePresence(myKey);
  }

  Future<void> _startRecording() async {
    // Guard against a stray/duplicate tap re-entering this while a previous
    // recording is still being stopped/sent, which could otherwise start a
    // second recording session on top of one that hasn't fully torn down.
    if (_isRecording || _isSendingVoice || _isStoppingRecording) {
      LogService.log(
          'Voice: _startRecording ignored — already recording=$_isRecording sending=$_isSendingVoice stopping=$_isStoppingRecording');
      return;
    }
    try {
      final granted = await Permission.microphone.request();
      if (!granted.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required for voice notes.')),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      _recordingPath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.ogg';
      LogService.log('Voice: _startRecording using path $_recordingPath');

      await VoiceService().startRecording(_recordingPath!);
      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration++;
        });
      });
    } catch (e) {
      LogService.log('Error starting recording: $e');
    }
  }

  Future<void> _stopAndSendRecording() async {
    // Guard against the send tap firing twice in quick succession (no
    // debounce on the GestureDetector), which would otherwise call
    // VoiceService().stopRecording() twice for the same session.
    if (_isStoppingRecording) {
      LogService.log('Voice: _stopAndSendRecording ignored — already stopping');
      return;
    }
    _isStoppingRecording = true;
    try {
      _recordingTimer?.cancel();
      final path = await VoiceService().stopRecording();
      setState(() => _isRecording = false);
      LogService.log(
          'Voice: stopRecording returned path=$path (expected _recordingPath=$_recordingPath), duration=$_recordingDuration');

      if (path == null || _recordingDuration < 1) {
        LogService.log('Recording too short or null. Discarding.');
        return;
      }

      setState(() => _isSendingVoice = true);

      try {
        final partnerPubKey = await CryptoService().fetchPartnerPublicKey();
        if (partnerPubKey != null) {
          final sharedKey = await CryptoService().getSharedKey(partnerPubKey);
          final encryptedVoiceJson = await VoiceService().encryptVoice(path, sharedKey);

          if (encryptedVoiceJson != null) {
            final encryptedTextMap = await CryptoService().encryptText('[Voice Message]', sharedKey);
            final textToSend = jsonEncode(encryptedTextMap);

            await _firestore.sendMessage(
              _coupleId,
              Message(
                id: const Uuid().v4(),
                senderId: _myUid,
                text: textToSend,
                type: MessageType.voice,
                audioUrl: encryptedVoiceJson,
                duration: _recordingDuration,
                sentAt: DateTime.now(),
                readBy: [_myUid],
              ),
              senderName: _auth.myName,
            );

            final myKey = _auth.isRay ? 'ray' : 'aproo';
            await _firestore.updatePresence(myKey);
          }
        }
      } catch (e) {
        LogService.log('Error uploading or sending voice message: $e');
      } finally {
        setState(() => _isSendingVoice = false);
        _recordingPath = null;
        _recordingDuration = 0;
      }
    } finally {
      _isStoppingRecording = false;
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    await VoiceService().stopRecording();
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });
    if (_recordingPath != null) {
      final file = File(_recordingPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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
        titleSpacing: _searchActive ? 4 : null,
        title: _searchActive
            ? Container(
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
                          hintText: 'Search messages…',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
                        onChanged: (v) => setState(() => _searchQuery = v.trim()),
                      ),
                    ),
                  ],
                ),
              )
            : const Text('Raayyy & Aproo'),
        actions: [
          if (_searchActive) ...[
            if (_loadingAllMessages)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: _activateSearch,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _buildMessageList(),
                if (!_searchActive)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: AnimatedOpacity(
                      opacity: _showScrollToBottom ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: IgnorePointer(
                        ignoring: !_showScrollToBottom,
                        child: FloatingActionButton.small(
                          onPressed: _scrollToBottom,
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.primary,
                          elevation: 3,
                          shape: CircleBorder(
                            side: BorderSide(color: AppTheme.divider, width: 0.5),
                          ),
                          child: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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

        bool showDateHeader = false;
        if (i == display.length - 1) {
          showDateHeader = true;
        } else {
          final olderMsg = display[i + 1];
          final dateCurrent = msg.sentAt;
          final dateOlder = olderMsg.sentAt;
          if (dateCurrent.year != dateOlder.year ||
              dateCurrent.month != dateOlder.month ||
              dateCurrent.day != dateOlder.day) {
            showDateHeader = true;
          }
        }

        Widget buildDateHeader(DateTime date) {
          String text = '';
          final now = DateTime.now();
          if (date.year == now.year && date.month == now.month && date.day == now.day) {
            text = 'Today';
          } else if (date.year == now.year && date.month == now.month && date.day == now.day - 1) {
            text = 'Yesterday';
          } else {
            text = DateFormat('MMMM d, yyyy').format(date);
          }

          return Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          );
        }

        final msgWidget = AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          color: msg.id == _highlightedId
              ? AppTheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          child: _SwipeableMessage(
            isMe: msg.senderId == _myUid,
            onReply: () => _setReply(msg),
            child: _MessageBubble(
              message: msg,
              displayText: _getOrDecryptText(msg),
              replyToDisplayText: _getOrDecryptReplyText(msg),
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

        if (showDateHeader) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildDateHeader(msg.sentAt),
              msgWidget,
            ],
          );
        }
        return msgWidget;
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
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(
                    left: BorderSide(color: AppTheme.primary, width: 4),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.reply_rounded,
                            size: 14, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Replying to ${_replyTo!.senderId == _myUid ? "yourself" : _auth.partnerDisplayName}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _clearReply,
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getOrDecryptText(_replyTo!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textDark,
                          height: 1.2),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _isSendingVoice
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      ),
                    )
                  : _isRecording
                      ? Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Recording... ${_formatDuration(_recordingDuration)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.redAccent,
                                fontSize: 15,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.delete_rounded, color: AppTheme.textMuted),
                              onPressed: _cancelRecording,
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _stopAndSendRecording,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _textCtrl,
                                minLines: 1,
                                maxLines: 6,
                                style: const TextStyle(fontSize: 15),
                                decoration: InputDecoration(
                                  hintText: 'Message...',
                                  hintStyle: const TextStyle(color: AppTheme.textMuted),
                                  filled: true,
                                  fillColor: const Color(0xFFF3EFEF),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 11),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: const BorderSide(color: AppTheme.primary, width: 1.0),
                                  ),
                                ),
                                textCapitalization: TextCapitalization.sentences,
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _textCtrl.text.trim().isEmpty ? _startRecording : _send,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary.withValues(alpha: 0.25),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _textCtrl.text.trim().isEmpty ? Icons.mic_rounded : Icons.send_rounded,
                                  color: Colors.white,
                                  size: 18,
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

class _SwipeableMessageState extends State<_SwipeableMessage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _translationAnimation;
  bool _triggered = false;
  double _dragExtent = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // Custom springy curve for sliding back
    _translationAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuad,
    ).drive(
      Tween<double>(begin: 0.0, end: 72.0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _dragExtent += details.delta.dx;
    if (_dragExtent < 0) _dragExtent = 0;

    // Apply soft damping resistance
    final double maxDrag = 120.0;
    final double progress = (_dragExtent / maxDrag).clamp(0.0, 1.0);

    // Trigger haptic when reaching 55% of maxDrag
    if (progress >= 0.55 && !_triggered) {
      _triggered = true;
      HapticFeedback.lightImpact();
    } else if (progress < 0.55 && _triggered) {
      _triggered = false;
    }

    _controller.value = progress;
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_triggered) {
      widget.onReply();
    }
    // Bounce back smoothly
    _controller.animateTo(0.0, curve: Curves.elasticOut, duration: const Duration(milliseconds: 350));
    _dragExtent = 0.0;
    _triggered = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      behavior: HitTestBehavior.translucent,
      child: AnimatedBuilder(
        animation: _translationAnimation,
        builder: (context, child) {
          final offset = _translationAnimation.value;
          final isTriggeredAtLimit = _controller.value >= 0.55;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (offset > 4)
                Positioned(
                  left: -32 + (offset * 0.5), // Parallax entry effect
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isTriggeredAtLimit
                            ? AppTheme.primary
                            : AppTheme.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.reply_rounded,
                        color: isTriggeredAtLimit ? Colors.white : AppTheme.primary,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(offset, 0),
                child: widget.child,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Message message;
  final String displayText;
  final String? replyToDisplayText;
  final bool isMe;
  final bool showReceipt;
  final String myUid;
  final VoidCallback onLongPress;
  final void Function(String emoji) onReaction;
  final VoidCallback? onReplyTap;
  final String searchQuery;

  const _MessageBubble({
    required this.message,
    required this.displayText,
    this.replyToDisplayText,
    required this.isMe,
    required this.showReceipt,
    required this.myUid,
    required this.onLongPress,
    required this.onReaction,
    this.onReplyTap,
    this.searchQuery = '',
  });

  Widget _buildImageMessage(BuildContext context) {
    final isLocalImage = message.imageUrl?.startsWith('/') ?? false;
    final isRead = message.readBy.length > 1;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GestureDetector(
        onTap: () => _showFullScreenImage(context, message.imageUrl!),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 240,
            maxHeight: 240,
          ),
          child: Stack(
            fit: StackFit.loose,
            alignment: Alignment.center,
            children: [
              if (isLocalImage)
                Image.file(
                  File(message.imageUrl!),
                  width: 240,
                  height: 240,
                  fit: BoxFit.cover,
                )
              else
                CachedNetworkImage(
                  imageUrl: message.imageUrl!,
                  width: 240,
                  height: 240,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 240,
                    height: 240,
                    color: AppTheme.divider,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 240,
                    height: 240,
                    color: AppTheme.divider,
                    child: const Icon(Icons.error_outline_rounded, color: Colors.red),
                  ),
                ),
                
              // Local Upload Progress Overlay
              if (isLocalImage)
                Container(
                  width: 240,
                  height: 240,
                  color: Colors.black.withValues(alpha: 0.4),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ),

              // Glassmorphic / translucent bottom-right timestamp overlay
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTimestamp(message.sentAt),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                      if (isMe && showReceipt) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isRead ? Icons.done_all_rounded : Icons.done_rounded,
                          size: 12,
                          color: isRead ? const Color(0xFFE8715A) : Colors.white60,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    final isLocal = imageUrl.startsWith('/');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: isLocal
                  ? Image.file(File(imageUrl))
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white),
                      errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime sentAt) {
    final diff = DateTime.now().difference(sentAt);
    if (diff.inMinutes < 60) {
      return timeago.format(sentAt, locale: 'en_short');
    }
    return DateFormat.jm().format(sentAt);
  }

  Widget _buildMessageText(String text, bool isMe, {bool isEmojiOnly = false}) {
    if (isEmojiOnly) {
      final emojiCount = _countEmojis(text);
      double size = 15;
      if (emojiCount == 1) {
        size = 40;
      } else if (emojiCount == 2) {
        size = 30;
      } else if (emojiCount == 3) {
        size = 28;
      }

      return Text(text, style: TextStyle(fontSize: size));
    }

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
    final isEmojiOnly = _isEmojiOnly(displayText);

    final isImage = message.type == MessageType.image;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
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
                    padding: isEmojiOnly 
                        ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
                        : isImage
                            ? EdgeInsets.zero
                            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: isEmojiOnly 
                        ? const BoxDecoration(color: Colors.transparent)
                        : isImage
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.divider),
                              )
                            : BoxDecoration(
                                color: isMe ? AppTheme.primary : AppTheme.surface,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 18),
                                ),
                                border: isMe ? null : Border.all(color: AppTheme.divider),
                              ),
                    child: Column(
                      crossAxisAlignment: isEmojiOnly 
                          ? (isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start)
                          : CrossAxisAlignment.start,
                      children: [
                        // Reply preview — tappable to scroll to original
                        if (replyToDisplayText != null)
                          GestureDetector(
                            onTap: onReplyTap,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Colors.white.withValues(alpha: 0.16)
                                    : AppTheme.primaryLight.withValues(alpha: 0.75),
                                borderRadius: const BorderRadius.all(Radius.circular(6)),
                                border: Border(
                                  left: BorderSide(
                                    color: isMe
                                        ? Colors.white.withValues(alpha: 0.85)
                                        : AppTheme.primary,
                                    width: 3.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.reply_rounded,
                                    size: 12,
                                    color: isMe
                                        ? Colors.white70
                                        : AppTheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      replyToDisplayText!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isMe
                                            ? Colors.white.withValues(alpha: 0.9)
                                            : AppTheme.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (isImage)
                          _buildImageMessage(context)
                        else ...[
                          if (message.type == MessageType.voice)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              // Without a key tied to message identity, this
                              // list (built with reverse: true, so every
                              // older message shifts position when a new one
                              // arrives) lets Flutter reuse this widget's
                              // State — including its cached decrypted audio
                              // path and player — for a different message
                              // that happens to land at the same position.
                              child: VoicePlaybackWidget(
                                key: ValueKey(message.id),
                                message: message,
                                isMe: isMe,
                              ),
                            )
                          else
                            _buildMessageText(displayText, isMe, isEmojiOnly: isEmojiOnly),
                          // ── Timestamp + receipt inside the bubble ──────────
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTimestamp(message.sentAt),
                                  style: TextStyle(
                                    color: isMe && !isEmojiOnly
                                        ? Colors.white.withValues(alpha: 0.6)
                                        : AppTheme.textMuted,
                                    fontSize: 10,
                                  ),
                                ),
                                if (isMe && showReceipt) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    isRead
                                        ? Icons.done_all_rounded
                                        : Icons.done_rounded,
                                    size: 12,
                                    color: isRead
                                        ? (isEmojiOnly ? AppTheme.primary : Colors.white.withValues(alpha: 0.85))
                                        : (isEmojiOnly ? AppTheme.textMuted : Colors.white.withValues(alpha: 0.45)),
                                  ),
                                  if (isRead && partnerReadTime != null) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      'Read ${DateFormat.jm().format(partnerReadTime)}',
                                      style: TextStyle(
                                        color: isEmojiOnly ? AppTheme.textMuted : Colors.white.withValues(alpha: 0.6),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Reactions stay outside the bubble
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VoicePlaybackWidget extends StatefulWidget {
  final Message message;
  final bool isMe;

  const VoicePlaybackWidget({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  State<VoicePlaybackWidget> createState() => _VoicePlaybackWidgetState();
}

class _VoicePlaybackWidgetState extends State<VoicePlaybackWidget> {
  FlutterSoundPlayer? _player;
  bool _isPlaying = false;
  bool _loading = false;
  String? _decryptedLocalPath;
  double _playPosition = 0.0;
  Duration _currentDuration = Duration.zero;
  Duration _totalDuration = Duration.zero;
  StreamSubscription? _playerSub;

  static const List<double> _waveformAmplitudes = [
    12.0, 24.0, 16.0, 32.0, 20.0, 28.0, 14.0, 22.0, 18.0, 30.0,
    15.0, 26.0, 20.0, 34.0, 18.0, 24.0, 12.0, 28.0, 16.0, 22.0,
    14.0, 20.0, 18.0, 26.0, 15.0, 24.0, 12.0, 18.0, 16.0, 10.0
  ];

  @override
  void initState() {
    super.initState();
    _player = FlutterSoundPlayer();
    _totalDuration = Duration(seconds: widget.message.duration ?? 0);
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _player?.closePlayer();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    if (_player!.isOpen()) return;
    await _player!.openPlayer();
    await _player!.setSubscriptionDuration(const Duration(milliseconds: 100));
  }

  Future<void> _downloadAndDecrypt() async {
    if (_decryptedLocalPath != null) return;
    setState(() => _loading = true);

    try {
      final partnerPubKey = await CryptoService().fetchPartnerPublicKey();
      if (partnerPubKey != null) {
        final sharedKey = await CryptoService().getSharedKey(partnerPubKey);
        final path = await VoiceService().decryptVoice(widget.message.audioUrl!, sharedKey);
        if (mounted) {
          setState(() {
            _decryptedLocalPath = path;
            _loading = false;
          });
        }
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      LogService.log('Error decrypting voice message: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePlay() async {
    if (_loading) return;

    if (_decryptedLocalPath == null) {
      await _downloadAndDecrypt();
      if (_decryptedLocalPath == null) return;
    }

    await _initPlayer();

    try {
      if (_isPlaying) {
        await _player!.pausePlayer();
        setState(() => _isPlaying = false);
      } else if (_player!.isPaused) {
        await _player!.resumePlayer();
        setState(() => _isPlaying = true);
      } else {
        _playerSub?.cancel();
        await _player!.startPlayer(
          fromURI: _decryptedLocalPath,
          codec: Codec.opusOGG,
          whenFinished: () {
            // Without explicitly cancelling the progress subscription and
            // stopping the player here, flutter_sound keeps firing
            // onProgress with the last known position/duration forever,
            // flooding the console and leaving the native player session
            // open.
            _playerSub?.cancel();
            _playerSub = null;
            _player?.stopPlayer();
            if (mounted) {
              setState(() {
                _isPlaying = false;
                _playPosition = 0.0;
                _currentDuration = Duration.zero;
              });
            }
          },
        );
        _playerSub = _player!.onProgress!.listen((e) {
          setState(() {
            _currentDuration = e.position;
            _totalDuration = e.duration;
            if (e.duration.inMilliseconds > 0) {
              _playPosition = e.position.inMilliseconds / e.duration.inMilliseconds;
            }
          });
        });
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      LogService.log('Playback error: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.isMe ? Colors.white : AppTheme.primary;
    final mutedColor = widget.isMe ? Colors.white38 : AppTheme.divider;

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.isMe ? Colors.white24 : AppTheme.primaryLight,
                shape: BoxShape.circle,
              ),
              child: _loading
                  ? Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                        ),
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: themeColor,
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;

                    void handleScrub(double dx) {
                      if (_totalDuration.inMilliseconds <= 0) return;
                      final ratio = (dx / width).clamp(0.0, 1.0);
                      final targetMs = (ratio * _totalDuration.inMilliseconds).toInt();

                      setState(() {
                        _playPosition = ratio;
                        _currentDuration = Duration(milliseconds: targetMs);
                      });

                      if (_player!.isOpen() && !_loading && _decryptedLocalPath != null) {
                        _player!.seekToPlayer(Duration(milliseconds: targetMs));
                      }
                    }

                    return GestureDetector(
                      onTapDown: (details) => handleScrub(details.localPosition.dx),
                      onHorizontalDragUpdate: (details) => handleScrub(details.localPosition.dx),
                      child: Container(
                        height: 25,
                        color: Colors.transparent, // Expand tap target hit area
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(_waveformAmplitudes.length, (idx) {
                            final amplitude = _waveformAmplitudes[idx];
                            final barProgress = idx / _waveformAmplitudes.length;
                            final isActive = barProgress <= _playPosition;
                            return Container(
                              width: 2.5,
                              height: amplitude,
                              decoration: BoxDecoration(
                                color: isActive ? themeColor : mutedColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_currentDuration),
                      style: TextStyle(
                        fontSize: 10,
                        color: widget.isMe ? Colors.white70 : AppTheme.textMuted,
                      ),
                    ),
                    Text(
                      _formatDuration(_totalDuration),
                      style: TextStyle(
                        fontSize: 10,
                        color: widget.isMe ? Colors.white70 : AppTheme.textMuted,
                      ),
                    ),
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
