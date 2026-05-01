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
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  Future<void> _submitEmail() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSignUp) {
        await _auth.signUp(
            _emailCtrl.text.trim(), _passwordCtrl.text, _nameCtrl.text.trim());
      } else {
        await _auth.signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
      }
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
    try {
      await _auth.signInWithGoogle();
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('not allowed')) return 'This app is private — only Ray & Aproo can sign in.';
    if (raw.contains('wrong-password') || raw.contains('invalid-credential')) return 'Wrong email or password.';
    if (raw.contains('user-not-found')) return 'No account found with that email.';
    if (raw.contains('email-already-in-use')) return 'An account with that email already exists.';
    if (raw.contains('network')) return 'Check your internet connection.';
    return 'Something went wrong. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Text('tether',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    letterSpacing: -1,
                  )),
              const SizedBox(height: 6),
              Text('just the two of you',
                  style: GoogleFonts.dmSans(
                      color: AppTheme.textMuted, fontSize: 14)),
              const SizedBox(height: 52),

              // Google Sign-In button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _googleLoading ? null : _signInWithGoogle,
                  icon: _googleLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Image.network(
                          'https://www.google.com/favicon.ico',
                          width: 18,
                          height: 18,
                          errorBuilder: (context, error, stack) =>
                              const Icon(Icons.login, size: 18),
                        ),
                  label: const Text('Continue with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppTheme.divider),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    foregroundColor: AppTheme.textDark,
                    textStyle: GoogleFonts.dmSans(
                        fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Row(children: [
                const Expanded(child: Divider(color: AppTheme.divider)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textMuted)),
                ),
                const Expanded(child: Divider(color: AppTheme.divider)),
              ]),
              const SizedBox(height: 24),

              if (_isSignUp) ...[
                _label('Your name'),
                const SizedBox(height: 8),
                TextField(
                    controller: _nameCtrl,
                    decoration:
                        const InputDecoration(hintText: 'Ray or Aproo')),
                const SizedBox(height: 20),
              ],
              _label('Email'),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    const InputDecoration(hintText: 'you@email.com'),
              ),
              const SizedBox(height: 20),
              _label('Password'),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(hintText: '••••••••'),
                onSubmitted: (_) => _submitEmail(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!,
                      style:
                          const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              ],

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submitEmail,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isSignUp ? 'Create account' : 'Sign in'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : "Don't have an account? Sign up",
                    style:
                        const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textMuted,
          letterSpacing: 0.3));
}
