import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'location_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int) onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  final _firestore = FirestoreService();
  late AnimationController _pokeController;
  late Animation<double> _pokeScale;
  bool _pokeSent = false;

  // Update this to your actual anniversary / together-since date
  static final DateTime _togetherSince = DateTime(2026, 4, 9);

  String get _daysTogether =>
      DateTime.now().difference(_togetherSince).inDays.toString();

  @override
  void initState() {
    super.initState();
    _pokeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _pokeScale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pokeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pokeController.dispose();
    super.dispose();
  }

  Future<void> _sendPoke() async {
    await _pokeController.forward();
    await _pokeController.reverse();
    HapticFeedback.mediumImpact();
    setState(() => _pokeSent = true);
    await _firestore.sendPoke(
        _auth.currentUser!.uid, 'partner', _auth.myName);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _pokeSent = false);
  }

  Future<void> _signOut() async {
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              _buildDaysCard(),
              const SizedBox(height: 20),
              _buildPokeCard(),
              const SizedBox(height: 20),
              _buildQuickActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(greeting,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textMuted)),
            Text('Ray & Aproo',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                )),
          ],
        ),
        GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Sign out?'),
              content: Text('Signing out as ${_auth.myName}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: _signOut,
                    child: const Text('Sign out',
                        style: TextStyle(color: Colors.red))),
              ],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.favorite, color: AppTheme.primary, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildDaysCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8715A), Color(0xFFB5838D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Together for',
              style: GoogleFonts.dmSans(
                  color: Colors.white70, fontSize: 13, letterSpacing: 0.3)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_daysTogether,
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  )),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('days',
                    style: GoogleFonts.dmSans(
                        color: Colors.white70, fontSize: 20)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Since ${_formatDate(_togetherSince)}',
            style: GoogleFonts.dmSans(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildPokeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Poke ${_auth.partnerName}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  _pokeSent
                      ? '${_auth.partnerName} has been poked! 💕'
                      : 'Let them know you\'re thinking of them',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ScaleTransition(
            scale: _pokeScale,
            child: GestureDetector(
              onTap: _pokeSent ? null : _sendPoke,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _pokeSent ? Icons.favorite : Icons.touch_app_rounded,
                  color: AppTheme.primary,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick access',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textMuted, letterSpacing: 0.3)),
        const SizedBox(height: 12),
        Row(
          children: [
            _actionTile(Icons.check_circle_outline_rounded, 'To-do',
                () => widget.onNavigate(2)),
            const SizedBox(width: 12),
            _actionTile(Icons.chat_bubble_outline_rounded, 'Chat',
                () => widget.onNavigate(1)),
            const SizedBox(width: 12),
            _actionTile(Icons.location_on_outlined, 'Location', () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LocationScreen()));
            }),
          ],
        ),
      ],
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppTheme.primary, size: 24),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
