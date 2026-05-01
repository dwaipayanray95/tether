import 'package:flutter/material.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Uncomment after adding google-services.json:
  // await Firebase.initializeApp();
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
      // Show app directly for now — swap for the StreamBuilder once Firebase is live
      home: const MainShell(),

      // --- UNCOMMENT after Firebase setup ---
      // home: StreamBuilder<User?>(
      //   stream: FirebaseAuth.instance.authStateChanges(),
      //   builder: (context, snapshot) {
      //     if (snapshot.connectionState == ConnectionState.waiting) {
      //       return const Scaffold(
      //         body: Center(child: CircularProgressIndicator()),
      //       );
      //     }
      //     return snapshot.hasData ? const MainShell() : const LoginScreen();
      //   },
      // ),
    );
  }
}
