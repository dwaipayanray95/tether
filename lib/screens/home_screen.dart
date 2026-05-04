import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import 'search_screen.dart';

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

  // Together since date
  static final DateTime _togetherSince = DateTime(2026, 4, 9);

  // Distance
  Position? _myPosition;
  Map<String, dynamic>? _partnerLocation;
  bool _locationLoading = true;

  // Last seen
  Timestamp? _rayLastSeen;
  bool _rayIsOnline = false;
  Timestamp? _aprooLastSeen;
  bool _aprooIsOnline = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _partnerLocSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rayPresenceSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _aprooPresenceSub;

  double? get _distanceKm {
    final p = _partnerLocation;
    final my = _myPosition;
    if (p == null || my == null) return null;
    final lat = p['lat'] as double?;
    final lng = p['lng'] as double?;
    if (lat == null || lng == null) return null;
    return Geolocator.distanceBetween(my.latitude, my.longitude, lat, lng) /
        1000;
  }

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
    _initLocation();
    _initPresence();
  }

  @override
  void dispose() {
    _pokeController.dispose();
    _partnerLocSub?.cancel();
    _rayPresenceSub?.cancel();
    _aprooPresenceSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) {
      if (mounted) setState(() => _locationLoading = false);
      return;
    }

    final myKey = _auth.isRay ? 'ray' : 'aproo';
    final partnerKey = _auth.isRay ? 'aproo' : 'ray';

    final myPos = await LocationService.getCurrentPosition();
    if (myPos != null && mounted) {
      setState(() => _myPosition = myPos);
      await LocationService.updateIfNeeded(myPos, myKey, _auth.myName);
    }

    _partnerLocSub = LocationService.locationStream(partnerKey).listen((snap) {
      if (mounted) {
        setState(() {
          _partnerLocation = snap.data();
          _locationLoading = false;
        });
      }
    });
  }

  void _initPresence() {
    _rayPresenceSub = _firestore.presenceStream('ray').listen((snap) {
      final data = snap.data();
      if (mounted) {
        setState(() {
          _rayLastSeen = data?['lastSeen'] as Timestamp?;
          _rayIsOnline = data?['isOnline'] as bool? ?? false;
        });
      }
    });
    _aprooPresenceSub = _firestore.presenceStream('aproo').listen((snap) {
      final data = snap.data();
      if (mounted) {
        setState(() {
          _aprooLastSeen = data?['lastSeen'] as Timestamp?;
          _aprooIsOnline = data?['isOnline'] as bool? ?? false;
        });
      }
    });
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
              _buildDistanceCard(),
              const SizedBox(height: 20),
              _buildLastSeen(),
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
        Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SearchScreen(onNavigate: widget.onNavigate),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: const Icon(Icons.search_rounded,
                    color: AppTheme.textMuted, size: 20),
              ),
            ),
            const SizedBox(width: 10),
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
                child: const Icon(Icons.favorite,
                    color: AppTheme.primary, size: 22),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDistanceCard() {
    final dist = _distanceKm;

    String label;
    String headline;
    String subline;

    if (_locationLoading) {
      label = 'Finding location…';
      headline = '';
      subline = '';
    } else if (dist == null) {
      label = 'Location';
      headline = 'Waiting for ${_auth.partnerName}\'s location';
      subline = 'Updates when they open the app';
    } else if (dist < 1.0) {
      label = 'Right here';
      headline = "You're right beside each other";
      subline = 'Since ${_formatDate(_togetherSince)}';
    } else {
      label = 'Distance';
      headline = '${_auth.partnerName} is ${_formatKm(dist)} away';
      subline = 'Since ${_formatDate(_togetherSince)}';
    }

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
      child: _locationLoading
          ? const SizedBox(
              height: 60,
              child: Center(
                  child: CircularProgressIndicator(color: Colors.white54)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.dmSans(
                        color: Colors.white70,
                        fontSize: 13,
                        letterSpacing: 0.3)),
                const SizedBox(height: 8),
                Text(headline,
                    style: GoogleFonts.playfairDisplay(
                      color: Colors.white,
                      fontSize: headline.length > 24 ? 21 : 27,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    )),
                if (subline.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(subline,
                      style: GoogleFonts.dmSans(
                          color: Colors.white54, fontSize: 12)),
                ],
              ],
            ),
    );
  }

  Widget _buildLastSeen() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Expanded(
              child: _lastSeenTile('Ray', _rayIsOnline, _rayLastSeen)),
          Container(
              width: 1,
              height: 36,
              color: AppTheme.divider,
              margin: const EdgeInsets.symmetric(horizontal: 12)),
          Expanded(
              child:
                  _lastSeenTile('Aproo', _aprooIsOnline, _aprooLastSeen)),
        ],
      ),
    );
  }

  Widget _lastSeenTile(String name, bool isOnline, Timestamp? ts) {
    final label = isOnline
        ? 'Active now'
        : (ts == null
            ? 'Never seen'
            : timeago.format(ts.toDate(), locale: 'en_short'));

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOnline
                    ? Colors.green
                    : AppTheme.textMuted.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(name,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 3),
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ],
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

  String _formatKm(double km) {
    final rounded = km.round();
    if (rounded >= 1000) {
      final s = rounded.toString();
      final insert = s.length - 3;
      return '${s.substring(0, insert)},${s.substring(insert)} km';
    }
    return '$rounded km';
  }
}
