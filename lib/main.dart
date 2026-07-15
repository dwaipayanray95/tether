import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/notification_service.dart';
import 'services/nav_service.dart';
import 'services/log_service.dart';
import 'services/music_sync_service.dart';
import 'theme/app_theme.dart';
import 'config/env_config.dart';
import 'package:google_sign_in/google_sign_in.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // serverClientId enables requestOfflineAccess() (see AuthService /
  // BackgroundSyncAuthService) — passing an empty string here is NOT the
  // same as omitting it, so this stays conditional until
  // EnvConfig.googleWebServerClientId is actually configured.
  await GoogleSignIn.instance.initialize(
    serverClientId: EnvConfig.googleWebServerClientId.isEmpty
        ? null
        : EnvConfig.googleWebServerClientId,
  );
  await LogService.init();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    LogService.log('FLUTTER ERROR: ${details.exceptionAsString()}\n${details.stack}');
  };

  LogService.log('App started');
  runApp(const TetherApp());
}

class TetherApp extends StatelessWidget {
  const TetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tether',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: navigatorKey,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              NotificationService.initialize();
              MusicSyncService.init();
            });
            return const MainShell();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
