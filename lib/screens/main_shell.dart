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
import '../services/google_drive_service.dart';
import '../services/crypto_service.dart';
import '../config/env_config.dart';
import '../config/google_scopes.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _coupleId = EnvConfig.coupleId;
  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _myPresenceKey => _auth.isRay ? 'ray' : 'aproo';

  DateTime? _lastUpdateCheck;

  static const _batteryChannel = MethodChannel('com.theawesomeray.tether/battery');
  Timer? _batteryTimer;
  int? _lastBatteryLevel;
  bool? _lastIsCharging;

  void _goToTab(int index) {
    LogService.log('Navigating to tab: $index');
    setState(() => _currentIndex = index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firestore.updatePresence(_myPresenceKey);
    _updateBatteryStatus();
    _batteryTimer = Timer.periodic(const Duration(minutes: 5), (_) => _updateBatteryStatus());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Validate Google API scopes, auto log out if new scopes are missing
      await _validateGoogleScopes();
      // Handle notification-triggered navigation on cold start
      _handlePendingNotification();
      // Check for update on launch
      _checkForUpdate();
      // Proactively check and request all permissions
      _requestAllPermissions();
      // Restore user preferences backup from Google Drive
      await _restorePrefsFromCloud();
      // Ensure E2EE is set up and key is backed up
      await _checkE2EESetup();
    });
  }

  Future<void> _validateGoogleScopes() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final isGoogleUser = user.providerData.any((p) => p.providerId == 'google.com');
      if (!isGoogleUser) return;

      final googleUser = await GoogleSignIn.instance.attemptLightweightAuthentication();

      if (googleUser == null) {
        LogService.log('Google Sign-In user not available on startup scope check. Skipping check until next operation.');
        return;
      }

      try {
        // Self-healing scope check: only ever a silent lookup. Android
        // requires authorizeScopes() (the interactive grant) to be
        // triggered by a real user tap, so we must never call it here in
        // the background — that was what caused the Google consent screen
        // to pop up repeatedly. Instead, if GoogleScopes.all has grown to
        // include scopes this signed-in user never granted, sign them out
        // so the normal login flow (AuthService.signInWithGoogle) requests
        // the full current scope set from a real button press.
        LogService.log('Google Sign-In: Checking cached scopes via authorizationForScopes');
        final auth = await googleUser.authorizationClient.authorizationForScopes(GoogleScopes.all);
        if (auth == null) {
          LogService.log('Google Sign-In: Missing cached scopes in authorizationForScopes. Logging out to force re-consent.');
          await _auth.signOut();
        } else {
          LogService.log('Google Sign-In: Cached scopes verified successfully');
        }
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('unimplemented') || errStr.contains('not implemented') || errStr.contains('notsupported')) {
          LogService.log('Google Sign-In: scopes check is unimplemented on this platform. Skipping check.');
        } else {
          LogService.log('Google Sign-In scope verification failed: $e. Logging out to be safe.');
          await _auth.signOut();
        }
      }
    } catch (e) {
      LogService.log('Outer Google Sign-In scope verification failed: $e. Logging out to be safe.');
      await _auth.signOut();
    }
  }

  Future<void> _updateBatteryStatus() async {
    try {
      final Map<dynamic, dynamic>? info = await _batteryChannel.invokeMethod('getBatteryInfo');
      if (info != null) {
        final level = info['batteryLevel'] as int? ?? -1;
        final isCharging = info['isCharging'] as bool? ?? false;
        if (level >= 0) {
          if (level == _lastBatteryLevel && isCharging == _lastIsCharging) {
            return; // Skip duplicate write!
          }
          _lastBatteryLevel = level;
          _lastIsCharging = isCharging;
          await _firestore.updateBatteryPresence(_myPresenceKey, level, isCharging);
        }
      }
    } catch (e) {
      LogService.log('Error getting battery level: $e');
    }
  }

  Future<void> _backupPrefsToCloud() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final Map<String, dynamic> prefsMap = {};
      for (final key in keys) {
        prefsMap[key] = prefs.get(key);
      }
      await GoogleDriveService().backupPreferences(prefsMap);
    } catch (e) {
      LogService.log('Failed to backup preferences: $e');
    }
  }

  Future<void> _restorePrefsFromCloud() async {
    try {
      final cloudPrefs = await GoogleDriveService().restorePreferences();
      if (cloudPrefs != null) {
        final prefs = await SharedPreferences.getInstance();
        for (final entry in cloudPrefs.entries) {
          final val = entry.value;
          if (val is bool) {
            await prefs.setBool(entry.key, val);
          } else if (val is int) {
            await prefs.setInt(entry.key, val);
          } else if (val is double) {
            await prefs.setDouble(entry.key, val);
          } else if (val is String) {
            await prefs.setString(entry.key, val);
          } else if (val is List) {
            await prefs.setStringList(entry.key, val.cast<String>());
          }
        }
        LogService.log('Preferences synced from Google Drive.');
      }
    } catch (e) {
      LogService.log('Failed to restore preferences: $e');
    }
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
    _batteryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LogService.log('App lifecycle state changed: $state');
    switch (state) {
      case AppLifecycleState.resumed:
        _firestore.updatePresence(_myPresenceKey);
        _updateBatteryStatus();
        _checkForUpdate();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handlePendingNotification();
        });
        break;
      default:
        _backupPrefsToCloud();
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
      ChatScreen(
        key: _chatKey,
        isActive: _currentIndex == 1,
      ),
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

  Future<void> _checkE2EESetup() async {
    if (!mounted) return;

    // Show a loading dialog while checking Google Drive backup
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppTheme.primary),
                SizedBox(height: 16),
                Text('Checking encryption status...'),
              ],
            ),
          ),
        ),
      ),
    );

    final myPubKey = await CryptoService().getPublicKey();
    final backup = await GoogleDriveService().restoreKeyBackup();
    
    if (!mounted) return;
    Navigator.pop(context); // Dismiss loading dialog

    if (myPubKey != null) {
      // Sync public key just in case it is missing on Firestore
      await _firestore.registerPublicKey(_myPresenceKey, myPubKey);
      
      // If we have local keys but NO backup on Google Drive, we must prompt to upload backup!
      if (backup == null) {
        _showBackupRequiredDialog();
      }
      return;
    }

    if (backup != null) {
      _showRestoreE2EEDialog(backup);
    } else {
      _showCreateE2EEDialog();
    }
  }

  void _showBackupRequiredDialog() {
    final pinCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Secure E2EE Backup', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Your E2EE keys are active locally, but not backed up to Google Drive. Please create a 4-digit PIN to upload your secure backup:'),
              const SizedBox(height: 16),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: 'Create 4-Digit PIN',
                  errorText: error,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final pin = pinCtrl.text.trim();
                if (pin.length != 4) {
                  setDialogState(() => error = 'PIN must be exactly 4 digits');
                  return;
                }
                try {
                  final privateKey = await CryptoService().getPrivateKey();
                  final publicKey = await CryptoService().getPublicKey();
                  if (privateKey != null && publicKey != null) {
                    final encryptedBackup = await CryptoService().encryptPrivateKey(pin, privateKey);
                    encryptedBackup['publicKey'] = publicKey;
                    await GoogleDriveService().backupKeyBackup(encryptedBackup);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setDialogState(() => error = 'Backup failed: $e');
                }
              },
              child: const Text('Back Up'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRestoreE2EEDialog(Map<String, dynamic> backup) {
    final pinCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Restore Encryption Keys', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('An encryption backup was found on Google Drive. Enter your 4-digit E2EE PIN to restore it:'),
              const SizedBox(height: 16),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: '4-Digit PIN',
                  errorText: error,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final pin = pinCtrl.text.trim();
                if (pin.length != 4) {
                  setDialogState(() => error = 'PIN must be exactly 4 digits');
                  return;
                }
                try {
                  final decryptedPrivateKey = await CryptoService().decryptPrivateKey(pin, backup);
                  final publicKey = backup['publicKey'] as String;

                  // Restore keys locally
                  await CryptoService().restoreKeys(publicKey, decryptedPrivateKey);
                  // Register public key to Firestore
                  await _firestore.registerPublicKey(_myPresenceKey, publicKey);

                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setDialogState(() => error = 'Incorrect PIN. Try again.');
                }
              },
              child: const Text('Restore'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateE2EEDialog() {
    final pinCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Secure Your Chats (E2EE)', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Create a 4-digit PIN to encrypt and back up your keys to Google Drive. You will need this PIN if you reinstall the app.'),
              const SizedBox(height: 16),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: 'Create 4-Digit PIN',
                  errorText: error,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final pin = pinCtrl.text.trim();
                if (pin.length != 4) {
                  setDialogState(() => error = 'PIN must be exactly 4 digits');
                  return;
                }
                try {
                  // Generate new keypair
                  final publicKey = await CryptoService().initializeKeys();
                  final privateKey = await CryptoService().getPrivateKey();

                  if (privateKey != null) {
                    // Encrypt and backup private key
                    final encryptedBackup = await CryptoService().encryptPrivateKey(pin, privateKey);
                    encryptedBackup['publicKey'] = publicKey; // Save public key alongside backup
                    await GoogleDriveService().backupKeyBackup(encryptedBackup);
                  }

                  // Register public key to Firestore
                  await _firestore.registerPublicKey(_myPresenceKey, publicKey);

                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setDialogState(() => error = 'Setup failed: $e');
                }
              },
              child: const Text('Set Up'),
            ),
          ],
        ),
      ),
    );
  }
}
