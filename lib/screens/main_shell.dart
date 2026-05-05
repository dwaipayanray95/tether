import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'todo_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/update_dialog.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';

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
  static const _coupleId = 'raayyy-aproo';
  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _myPresenceKey => _auth.isRaayyy ? 'raayyy' : 'aproo';

  void _goToTab(int index) => setState(() => _currentIndex = index);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Mark as online when app starts
    _firestore.updatePresence(_myPresenceKey, isOnline: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (NotificationService.pendingTab != null) {
        setState(() => _currentIndex = NotificationService.pendingTab!);
        NotificationService.pendingTab = null;
      }
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) UpdateDialog.checkAndShow(context);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _firestore.updatePresence(_myPresenceKey, isOnline: true);
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
    // Handle notification-triggered navigation
    if (NotificationService.pendingTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && NotificationService.pendingTab != null) {
          setState(() => _currentIndex = NotificationService.pendingTab!);
          NotificationService.pendingTab = null;
        }
      });
    }

    final screens = [
      HomeScreen(onNavigate: _goToTab),
      ChatScreen(key: _chatKey),
      const TodoScreen(),
    ];

    return PopScope(
      canPop: _currentIndex == 0 &&
          !(_currentIndex == 1 && _chatKey.currentState?.isSearchActive == true),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        
        if (_currentIndex == 1 && _chatKey.currentState?.isSearchActive == true) {
          _chatKey.currentState?.closeSearch();
        } else {
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
