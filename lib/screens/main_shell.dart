import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'todo_screen.dart';
import 'call_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/update_dialog.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/log_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final _chatKey = GlobalKey<ChatScreenState>();
  final _firestore = FirestoreService();
  final _auth = AuthService();
  static const _coupleId = 'ray-aproo';
  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _myPresenceKey => _auth.isRay ? 'ray' : 'aproo';

  StreamSubscription? _incomingCallSub;
  bool _callScreenOpen = false;

  /// Every callId that has been opened this session.
  /// Once a callId is in this set no further CallScreens will open for it,
  /// regardless of which trigger fires (Firestore stream, pendingCallId from
  /// any notification path, warm-resume, etc).
  final Set<String> _handledCallIds = {};

  /// Tracks the last time we pinged GitHub for an update.
  DateTime? _lastUpdateCheck;

  void _goToTab(int index) {
    LogService.log('Navigating to tab: $index');
    setState(() => _currentIndex = index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firestore.updatePresence(_myPresenceKey, isOnline: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Handle notification-triggered navigation on cold start
      _handlePendingNotification();
      // Listen for incoming calls via Firestore
      _listenIncomingCalls();
      // Check for update on launch
      _checkForUpdate();
    });
  }

  // ── Pending notification ──────────────────────────────────────────────────

  /// Consumes pendingTab / pendingCallId set by NotificationService.
  /// Safe to call multiple times — both fields are cleared before acting.
  void _handlePendingNotification() {
    final tab = NotificationService.pendingTab;
    if (tab != null) {
      LogService.log('Handling pending tab: $tab');
      NotificationService.pendingTab = null;
      setState(() => _currentIndex = tab);
    }
    final callId = NotificationService.pendingCallId;
    if (callId != null) {
      LogService.log('Handling pending call ID: $callId');
      NotificationService.pendingCallId = null; // clear BEFORE opening
      _openIncomingCallScreen(callId);
    }
  }

  // ── Update check ──────────────────────────────────────────────────────────

  void _checkForUpdate() {
    final now = DateTime.now();
    if (_lastUpdateCheck != null &&
        now.difference(_lastUpdateCheck!).inMinutes < 30) {
      LogService.log('Update check skipped (checked recently)');
      return;
    }
    _lastUpdateCheck = now;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) UpdateDialog.checkAndShow(context);
    });
  }

  // ── Incoming call stream ──────────────────────────────────────────────────

  void _listenIncomingCalls() {
    _incomingCallSub =
        CallService.incomingCallStream(_auth.myName).listen((doc) {
      if (doc == null) return;
      _openIncomingCallScreen(doc.id);
    });
  }

  // ── Open incoming call screen ─────────────────────────────────────────────

  /// Single, de-duplicated entry point for showing the incoming call UI.
  ///
  /// Uses [_handledCallIds] to ensure a given callId only ever opens ONE
  /// CallScreen, regardless of how many triggers arrive (Firestore snapshot
  /// re-emissions, stale pendingCallId from notification paths, lifecycle
  /// resume events, etc.).
  void _openIncomingCallScreen(String callId) {
    if (!mounted) return;

    if (_handledCallIds.contains(callId)) {
      LogService.log('Call $callId already handled — skipping duplicate');
      return;
    }

    if (_callScreenOpen) {
      // Mark handled so it won't re-trigger after the current screen closes.
      LogService.log('Call screen already open — marking $callId as handled');
      _handledCallIds.add(callId);
      return;
    }

    _handledCallIds.add(callId);
    LogService.log('Opening Incoming Call Screen: $callId');
    _callScreenOpen = true;
    Navigator.of(context)
        .push(MaterialPageRoute(
      builder: (_) => CallScreen(
        isOutgoing: false,
        partnerName: _auth.partnerName,
        callId: callId,
      ),
    ))
        .then((_) {
      _callScreenOpen = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingCallSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LogService.log('App lifecycle state changed: $state');
    switch (state) {
      case AppLifecycleState.resumed:
        _firestore.updatePresence(_myPresenceKey, isOnline: true);
        _checkForUpdate();
        // NotificationService sets pendingCallId/pendingTab from onMessageOpenedApp
        // or the async getNotificationAppLaunchDetails callback — consume them here.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handlePendingNotification();
        });
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _firestore.updatePresence(_myPresenceKey, isOnline: false);
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        onNavigate: _goToTab,
        onSelectMessage: (id) {
          LogService.log('Selected message from home: $id');
          setState(() => _currentIndex = 1);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _chatKey.currentState?.scrollToMessageById(id);
          });
        },
      ),
      ChatScreen(key: _chatKey),
      const TodoScreen(),
    ];

    return PopScope(
      canPop: _currentIndex == 0 &&
          !(_currentIndex == 1 &&
              _chatKey.currentState?.isSearchActive == true),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex == 1 &&
            _chatKey.currentState?.isSearchActive == true) {
          _chatKey.currentState?.closeSearch();
        } else {
          LogService.log('Back button pressed: returning to Home');
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.divider)),
          ),
          child: StreamBuilder<int>(
            stream: _firestore.unreadCountStream(_coupleId, _myUid),
            builder: (context, snap) {
              final unread = snap.data ?? 0;
              return BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: _goToTab,
                items: [
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Badge(
                      isLabelVisible: unread > 0 && _currentIndex != 1,
                      label: Text('$unread'),
                      child: const Icon(Icons.chat_bubble_outline_rounded),
                    ),
                    activeIcon: const Icon(Icons.chat_bubble_rounded),
                    label: 'Chat',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.check_circle_outline_rounded),
                    activeIcon: Icon(Icons.check_circle_rounded),
                    label: 'List',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
