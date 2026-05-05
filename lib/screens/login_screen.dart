import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _auth.signInWithGoogle();
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('not allowed')) return 'This app is private — only Raayyy & Aproo can sign in.';
    if (raw.contains('network')) return 'Check your internet connection.';
    if (raw.contains('cancelled') || raw.contains('canceled')) return '';
    return 'Something went wrong. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),
              // Logo / branding
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.favorite_rounded,
                    color: AppTheme.primary, size: 36),
              ),
              const SizedBox(height: 24),
              Text('tether',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                    letterSpacing: -1,
                  )),
              const SizedBox(height: 8),
              Text('just the two of you',
                  style: GoogleFonts.dmSans(
                      color: AppTheme.textMuted, fontSize: 15)),
              const Spacer(flex: 3),

              if (_error != null && _error!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
                const SizedBox(height: 16),
              ],

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _loading ? null : _signInWithGoogle,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.divider, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    backgroundColor: AppTheme.surface,
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.network(
                              'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                              width: 22,
                              height: 22,
                              errorBuilder: (context, error, stack) =>
                                  const Icon(Icons.g_mobiledata,
                                      size: 24, color: Colors.red),
                            ),
                            const SizedBox(width: 12),
                            Text('Continue with Google',
                                style: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textDark,
                                )),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Only Raayyy & Aproo can sign in',
                  style: GoogleFonts.dmSans(
                      color: AppTheme.textMuted, fontSize: 12)),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
