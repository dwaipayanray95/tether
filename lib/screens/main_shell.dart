import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'todo_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/update_dialog.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
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
    _firestore.updatePresence(_myPresenceKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Handle notification-triggered navigation on cold start
      _handlePendingNotification();
      // Check for update on launch
      _checkForUpdate();
      // Proactively check and request all permissions
      _requestAllPermissions();
    });
  }

  Future<void> _requestAllPermissions() async {
    LogService.log('Proactively requesting Android permissions in safe sequences...');

    // 1. Request standard permissions that use dialogs (Notification, Microphone, Camera, Phone, Foreground Location)
    Map<Permission, PermissionStatus> standardStatuses = {};
    try {
      final standardPermissions = [
        Permission.notification,
        Permission.microphone,
        Permission.camera,
        Permission.phone,
        Permission.location,
      ];

      LogService.log('Requesting Standard Permissions Batch...');
      standardStatuses = await standardPermissions.request();
      
      standardStatuses.forEach((permission, status) {
        LogService.log('Standard Permission ${permission.toString()}: $status');
      });
    } catch (e) {
      LogService.log('Error requesting standard batch: $e');
    }

    // 2. Kick off the interactive background/special settings permission prompts
    _checkSpecialPermissions();
  }

  Future<void> _checkSpecialPermissions() async {
    try {
      final isLocationAlwaysGranted = await Permission.locationAlways.isGranted;
      final isOverlayGranted = await Permission.systemAlertWindow.isGranted;
      final isAlarmGranted = await Permission.scheduleExactAlarm.isGranted;

      // Foreground location must be granted before requesting background location
      final isForegroundGranted = await Permission.location.isGranted;

      if (isForegroundGranted && !isLocationAlwaysGranted) {
        _showPermissionPrompt(
          title: '📍 Background Location Always',
          description: 'Tether needs "Allow all the time" location access so you and your partner can see each other\'s distance even when the app is closed.',
          permission: Permission.locationAlways,
        );
        return; // Prompt one at a time to prevent overlay clutter
      }

      if (!isOverlayGranted) {
        _showPermissionPrompt(
          title: '📞 Display Over Other Apps',
          description: 'Enable drawing over other apps to allow Tether to display full-screen calls and pokes instantly even when your phone is locked or you are using another app.',
          permission: Permission.systemAlertWindow,
        );
        return;
      }

      if (!isAlarmGranted) {
        _showPermissionPrompt(
          title: '⏰ Exact Alarm Schedule',
          description: 'Enable Exact Alarms to ensure Tether can schedule precise background checks and updates, keeping you and your partner perfectly connected.',
          permission: Permission.scheduleExactAlarm,
        );
        return;
      }
    } catch (e) {
      LogService.log('Error checking special permissions: $e');
    }
  }

  void _showPermissionPrompt({
    required String title,
    required String description,
    required Permission permission,
  }) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PopScope(
        canPop: false, // Prevent dismissing by tapping outside or back button
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                spreadRadius: 4,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: AppTheme.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  HapticFeedback.mediumImpact();
                  await permission.request();
                  // Re-check permissions sequentially after returning from settings
                  Future.delayed(const Duration(milliseconds: 1000), () {
                    if (mounted) _checkSpecialPermissions();
                  });
                },
                child: Text(
                  'Enable in Settings',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pending notification ──────────────────────────────────────────────────

  /// Consumes pendingTab set by NotificationService.
  /// Safe to call multiple times — field is cleared before acting.
  void _handlePendingNotification() {
    final tab = NotificationService.pendingTab;
    if (tab != null) {
      LogService.log('Handling pending tab: $tab');
      NotificationService.pendingTab = null;
      setState(() => _currentIndex = tab);
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LogService.log('App lifecycle state changed: $state');
    switch (state) {
      case AppLifecycleState.resumed:
        _firestore.updatePresence(_myPresenceKey);
        _checkForUpdate();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handlePendingNotification();
        });
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
