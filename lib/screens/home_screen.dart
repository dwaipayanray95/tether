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
import 'settings_screen.dart';
import 'search_screen.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int) onNavigate;
  final void Function(String messageId)? onSelectMessage;

  const HomeScreen({
    super.key,
    required this.onNavigate,
    this.onSelectMessage,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  final _firestore = FirestoreService();
  late AnimationController _pokeController;
  late Animation<double> _pokeScale;
  
  // Poke status
  String? _lastPokeFrom;
  StreamSubscription? _pokeSub;

  // Distance
  Position? _myPosition;
  Map<String, dynamic>? _partnerLocation;
  bool _locationLoading = true;
  bool _isRefreshing = false;

  // Last seen
  Timestamp? _rayLastSeen;
  bool _rayIsOnline = false;
  Timestamp? _aprooLastSeen;
  bool _aprooIsOnline = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _partnerLocSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _presenceSub;

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
    
    // Trigger location permission after the screen loads so the user sees the UI first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
    });
    
    _initPresence();
    _initPoke();
  }

  @override
  void dispose() {
    _pokeController.dispose();
    _partnerLocSub?.cancel();
    _presenceSub?.cancel();
    _pokeSub?.cancel();
    super.dispose();
  }

  void _initPoke() {
    _pokeSub = _firestore.pokeStatusStream(coupleId).listen((snap) {
      if (mounted && snap.exists) {
        setState(() => _lastPokeFrom = snap.data()?['lastFrom']);
      }
    });
  }

  Future<void> _initLocation() async {
    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) {
      if (mounted) setState(() => _locationLoading = false);
      return;
    }

    final myKey = _auth.isRay ? 'ray' : 'aproo';
    final partnerKey = _auth.isRay ? 'aproo' : 'ray';

    // Fetch initial state first so we don't show empty state
    final initialPartner = await LocationService.getLocation(partnerKey);
    if (mounted) {
      setState(() {
        _partnerLocation = initialPartner;
        if (initialPartner != null) _locationLoading = false;
      });
    }

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
          _isRefreshing = false;
        });
      }
    });
  }

  Future<void> _forceRefresh() async {
    if (_isRefreshing) return;
    HapticFeedback.mediumImpact();
    setState(() => _isRefreshing = true);

    final myKey = _auth.isRay ? 'ray' : 'aproo';
    final myPos = await LocationService.getCurrentPosition();
    if (myPos != null) {
      await LocationService.forceUpload(myPos, myKey, _auth.myName);
    }

    await LocationService.pingPartner(_auth.myName);

    // Timeout after 15s if no update received
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _isRefreshing) {
        setState(() => _isRefreshing = false);
      }
    });
  }

  void _initPresence() {
    _presenceSub = _firestore.presenceStream().listen((snap) {
      final data = snap.data();
      if (mounted && data != null) {
        setState(() {
          final r = data['ray'] as Map<String, dynamic>?;
          final a = data['aproo'] as Map<String, dynamic>?;

          if (r != null) {
            _rayLastSeen = r['lastSeen'] as Timestamp?;
            _rayIsOnline = r['isOnline'] as bool? ?? false;
          }
          if (a != null) {
            _aprooLastSeen = a['lastSeen'] as Timestamp?;
            _aprooIsOnline = a['isOnline'] as bool? ?? false;
          }
        });
      }
    });
  }

  Future<void> _sendPoke() async {
    final myUid = _auth.currentUser!.uid;
    if (_lastPokeFrom == myUid) return;

    await _pokeController.forward();
    await _pokeController.reverse();
    HapticFeedback.mediumImpact();
    
    await _firestore.sendPoke(coupleId, myUid, _auth.myName);
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
            Text('Raayyy & Aproo',
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
                  builder: (_) => SearchScreen(
                    onNavigate: widget.onNavigate,
                    onSelectMessage: widget.onSelectMessage,
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.search_rounded,
                    color: AppTheme.primary, size: 22),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
    final locality = _partnerLocation?['locality'] as String?;

    String headline;

    if (_locationLoading && _partnerLocation == null) {
      headline = 'Searching...';
    } else if (dist == null) {
      headline = 'Waiting for ${_auth.partnerName}';
    } else if (dist < 1.0) {
      headline = "You're right beside each other";
    } else {
      headline = '${_auth.partnerName} is ${_formatKm(dist)} away';
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 140),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8715A), Color(0xFFB5838D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          // Refresh / Loading Icon
          Positioned(
            top: 0,
            right: 0,
            child: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                : GestureDetector(
                    onTap: _forceRefresh,
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
          ),
          Center(
            child: _locationLoading && _partnerLocation == null
                ? const CircularProgressIndicator(color: Colors.white54)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(headline,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.playfairDisplay(
                            color: Colors.white,
                            fontSize: headline.length > 24 ? 21 : 27,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          )),
                      if (locality != null && dist != null && dist >= 1.0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Currently in $locality',
                          style: GoogleFonts.dmSans(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
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
              child: _lastSeenTile('Raayyy', _rayIsOnline, _rayLastSeen)),
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
    final myUid = _auth.currentUser?.uid;
    final canPoke = _lastPokeFrom != myUid;

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
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                            color: canPoke ? null : AppTheme.textMuted)),
                const SizedBox(height: 4),
                Text(
                  canPoke
                      ? 'Let them know you\'re thinking of them'
                      : 'You poked ${_auth.partnerName}! 💕',
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
              onTap: canPoke ? _sendPoke : null,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: canPoke
                      ? AppTheme.primaryLight
                      : AppTheme.divider.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  !canPoke ? Icons.favorite : Icons.touch_app_rounded,
                  color: canPoke ? AppTheme.primary : AppTheme.textMuted,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startCall() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(
        isOutgoing: true,
        partnerName: _auth.partnerName,
      ),
    ));
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
            _actionTile(Icons.call_rounded, 'Call', _startCall,
                iconColor: const Color(0xFF2E7D32),
                backgroundColor: const Color(0xFFE8F5E9)),
          ],
        ),
      ],
    );
  }

  Widget _actionTile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? iconColor,
    Color? backgroundColor,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: backgroundColor ?? AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: backgroundColor != null
                  ? (iconColor ?? AppTheme.primary).withValues(alpha: 0.25)
                  : AppTheme.divider,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: iconColor ?? AppTheme.primary, size: 24),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  String _formatKm(double km) {
    final rounded = km.round();
    if (rounded >= 1000) {
      final s = rounded.toString();
      final insert = s.length - 3;
      return '${s.substring(0, insert)},${s.substring(insert)} kms';
    }
    return '$rounded kms';
  }
}
