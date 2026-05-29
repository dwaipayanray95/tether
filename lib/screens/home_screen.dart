import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
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
import 'package:intl/intl.dart';
import '../services/music_sync_service.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

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
  late AnimationController _pulseController;
  late Animation<double> _pokeScale;
  
  // Poke status
  String? _lastPokeFrom;
  StreamSubscription? _pokeSub;
  bool _pokeCooldown = false;

  // Distance
  Position? _myPosition;
  Map<String, dynamic>? _partnerLocation;
  bool _locationLoading = true;
  bool _isRefreshing = false;

  // Proximity Sync via RTDB (AirTag mode)
  final _rtdb = FirebaseDatabase.instance;
  StreamSubscription? _rtdbProximitySub;
  StreamSubscription? _partnerRadarActiveSub;
  StreamSubscription<Position>? _myPositionSub;
  Timer? _rtdbProximityTimer;
  bool _proximityActive = false;
  bool _partnerRadarActive = false;
  double? _radarPartnerLat;
  double? _radarPartnerLng;

  // Compass Sensor Stream
  static const _compassChannel = EventChannel('com.theawesomeray.tether/compass');
  StreamSubscription? _compassSub;
  double _deviceHeading = 0.0;
  double _lastTargetDegrees = 0.0;
  double _turns = 0.0;

  // Last seen
  Timestamp? _rayLastSeen;
  Timestamp? _aprooLastSeen;
  Map<String, dynamic>? _rayMusic;
  Map<String, dynamic>? _aprooMusic;
  Map<String, dynamic>? _rayBattery;
  Map<String, dynamic>? _aprooBattery;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _partnerLocSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _presenceSub;

  double? get _distanceKm {
    final my = _myPosition;
    if (my == null) return null;
    
    double? plat;
    double? plng;
    if (_proximityActive && _radarPartnerLat != null && _radarPartnerLng != null) {
      plat = _radarPartnerLat;
      plng = _radarPartnerLng;
    } else if (_partnerLocation != null) {
      plat = _partnerLocation!['lat'] as double?;
      plng = _partnerLocation!['lng'] as double?;
    }
    
    if (plat == null || plng == null) return null;
    return Geolocator.distanceBetween(my.latitude, my.longitude, plat, plng) /
        1000;
  }

  // Sticky Notes Stream Cache
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stickyNotesStream;

  @override
  void initState() {
    super.initState();
    _stickyNotesStream = _firestore.stickyNotesStream(coupleId);
    _pokeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pokeScale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pokeController, curve: Curves.easeInOut),
    );
    
    // Trigger location permission after the screen loads so the user sees the UI first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      _initCompass();
    });
    
    _initPresence();
    _initPoke();

    final partnerKey = _auth.isRay ? 'aproo' : 'ray';
    _partnerRadarActiveSub = _rtdb.ref('proximity_sync/ray-aproo/$partnerKey/active').onValue.listen((event) {
      final active = event.snapshot.value as bool? ?? false;
      if (mounted) {
        setState(() {
          _partnerRadarActive = active;
        });
        _checkProximityRadar();
      }
    });
  }

  @override
  void dispose() {
    _pokeController.dispose();
    _pulseController.dispose();
    _partnerLocSub?.cancel();
    _presenceSub?.cancel();
    _pokeSub?.cancel();
    _compassSub?.cancel();
    _rtdbProximitySub?.cancel();
    _partnerRadarActiveSub?.cancel();
    _myPositionSub?.cancel();
    _rtdbProximityTimer?.cancel();
    super.dispose();
  }

  void _initCompass() {
    try {
      _compassSub = _compassChannel.receiveBroadcastStream().listen((event) {
        if (mounted) {
          setState(() {
            _deviceHeading = event as double? ?? 0.0;
            _updateTurns(_getRotationTarget());
          });
        }
      }, onError: (err) {
        debugPrint('Compass EventChannel error: $err');
      });
    } catch (e) {
      debugPrint('Failed to initialize compass stream: $e');
    }
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final lat1Rad = lat1 * (math.pi / 180.0);
    final lat2Rad = lat2 * (math.pi / 180.0);
    
    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) - math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);
    
    final bearing = math.atan2(y, x) * (180.0 / math.pi);
    return (bearing + 360.0) % 360.0;
  }

  double _getRotationTarget() {
    final dist = _distanceKm;
    if (dist == null || _myPosition == null) return 0.0;
    
    double? plat;
    double? plng;
    if (_proximityActive && _radarPartnerLat != null && _radarPartnerLng != null) {
      plat = _radarPartnerLat;
      plng = _radarPartnerLng;
    } else if (_partnerLocation != null) {
      plat = _partnerLocation!['lat'] as double?;
      plng = _partnerLocation!['lng'] as double?;
    }
    
    if (plat == null || plng == null) return 0.0;
    final b = _calculateBearing(
      _myPosition!.latitude,
      _myPosition!.longitude,
      plat,
      plng,
    );
    return (b - _deviceHeading) % 360.0;
  }

  void _updateTurns(double targetDegrees) {
    double diff = targetDegrees - _lastTargetDegrees;
    while (diff < -180.0) {
      diff += 360.0;
    }
    while (diff > 180.0) {
      diff -= 360.0;
    }
    _turns += diff / 360.0;
    _lastTargetDegrees = targetDegrees;
  }

  void _startProximityRadar() {
    if (_proximityActive) return;
    debugPrint('Starting Proximity Radar (3Hz RTDB mode)...');
    
    final partnerKey = _auth.isRay ? 'aproo' : 'ray';
    final myKey = _auth.isRay ? 'ray' : 'aproo';
    
    setState(() {
      _proximityActive = true;
    });

    // 1. Subscribe to partner's RTDB coordinates stream
    _rtdbProximitySub = _rtdb.ref('proximity_sync/ray-aproo/$partnerKey').onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && mounted) {
        setState(() {
          final lat = data['lat'];
          final lng = data['lng'];
          if (lat != null && lng != null) {
            _radarPartnerLat = (lat as num).toDouble();
            _radarPartnerLng = (lng as num).toDouble();
            _updateTurns(_getRotationTarget());
          }
        });
        _checkProximityRadar();
      }
    });

    // 2. Subscribe to high-frequency local geolocator stream for ourselves
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1, // update every meter
    );
    _myPositionSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      if (mounted) {
        setState(() {
          _myPosition = pos;
          _updateTurns(_getRotationTarget());
        });
        _checkProximityRadar();
      }
    });

    // 3. Periodic timer to write our position to RTDB at 3Hz (every 333ms)
    _rtdbProximityTimer = Timer.periodic(const Duration(milliseconds: 333), (timer) async {
      final pos = _myPosition;
      if (pos != null) {
        await _rtdb.ref('proximity_sync/ray-aproo/$myKey').set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'active': true,
          'updatedAt': ServerValue.timestamp,
        });
      }
    });
  }

  void _stopProximityRadar() {
    if (!_proximityActive) return;
    debugPrint('Stopping Proximity Radar...');
    
    _rtdbProximitySub?.cancel();
    _rtdbProximitySub = null;
    
    _myPositionSub?.cancel();
    _myPositionSub = null;
    
    _rtdbProximityTimer?.cancel();
    _rtdbProximityTimer = null;
    
    final myKey = _auth.isRay ? 'ray' : 'aproo';
    _rtdb.ref('proximity_sync/ray-aproo/$myKey/active').set(false);

    if (mounted) {
      setState(() {
        _proximityActive = false;
        _radarPartnerLat = null;
        _radarPartnerLng = null;
      });
    }
  }

  void _checkProximityRadar() {
    final dist = _distanceKm;
    final shouldBeActive = (dist != null && dist <= 0.15) || _partnerRadarActive;
    if (shouldBeActive) {
      if (!_proximityActive) {
        _startProximityRadar();
      }
    } else {
      if (_proximityActive) {
        _stopProximityRadar();
      }
    }
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
        _updateTurns(_getRotationTarget());
      });
      _checkProximityRadar();
    }

    final myPos = await LocationService.getCurrentPosition();
    if (myPos != null && mounted) {
      setState(() {
        _myPosition = myPos;
        _updateTurns(_getRotationTarget());
      });
      _checkProximityRadar();
      await LocationService.updateIfNeeded(myPos, myKey, _auth.myName);
    }

    _partnerLocSub = LocationService.locationStream(partnerKey).listen((snap) {
      if (mounted) {
        setState(() {
          _partnerLocation = snap.data();
          _locationLoading = false;
          _isRefreshing = false;
          _updateTurns(_getRotationTarget());
        });
        _checkProximityRadar();
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
            _rayMusic = r['music'] != null ? Map<String, dynamic>.from(r['music'] as Map) : null;
            _rayBattery = r['battery'] != null ? Map<String, dynamic>.from(r['battery'] as Map) : null;
          }
          if (a != null) {
            _aprooLastSeen = a['lastSeen'] as Timestamp?;
            _aprooMusic = a['music'] != null ? Map<String, dynamic>.from(a['music'] as Map) : null;
            _aprooBattery = a['battery'] != null ? Map<String, dynamic>.from(a['battery'] as Map) : null;
          }
        });
      }
    });
  }

  Future<void> _sendPoke() async {
    if (_pokeCooldown) return;
    
    final myUid = _auth.currentUser!.uid;

    setState(() => _pokeCooldown = true);
    
    await _pokeController.forward();
    await _pokeController.reverse();
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.heavyImpact();
    
    await _firestore.sendPoke(coupleId, myUid, _auth.myName);
    final myKey = _auth.isRay ? 'ray' : 'aproo';
    await _firestore.updatePresence(myKey);

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _pokeCooldown = false);
      }
    });
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
              const SizedBox(height: 14),
              _buildCompassCard(),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Our Sticky Board',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  GestureDetector(
                    onTap: _showStickyArchiveSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.archive_rounded, color: AppTheme.primary, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Archive',
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildStickyNotesBoard(),
              const SizedBox(height: 14),
              _buildMusicCard(),
              const SizedBox(height: 14),
              _buildPokeCard(),
              const SizedBox(height: 14),
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

    final partnerName = _auth.partnerName;
    final partnerLastSeen = _auth.isRay ? _aprooLastSeen : _rayLastSeen;
    final partnerOnline = partnerLastSeen != null &&
        DateTime.now().difference(partnerLastSeen.toDate()).inMinutes < 1;

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
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                )),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: partnerOnline ? Colors.green : AppTheme.textMuted.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  partnerOnline
                      ? '$partnerName is active now'
                      : (partnerLastSeen == null
                          ? '$partnerName is offline'
                          : '$partnerName was active ${timeago.format(partnerLastSeen.toDate(), locale: 'en_short')}'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
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

  Widget _buildCompassCard() {
    final dist = _distanceKm;
    final locality = _partnerLocation?['locality'] as String?;
    final partnerLastSeen = _auth.isRay ? _aprooLastSeen : _rayLastSeen;
    final partnerOnline = partnerLastSeen != null &&
        DateTime.now().difference(partnerLastSeen.toDate()).inMinutes < 1;

    final partnerBattery = _auth.isRay ? _aprooBattery : _rayBattery;
    final partnerMusic = _auth.isRay ? _aprooMusic : _rayMusic;

    String headline;
    if (_locationLoading && _partnerLocation == null) {
      headline = 'Searching...';
    } else if (dist == null) {
      headline = 'Waiting for ${_auth.partnerName}';
    } else if (_proximityActive) {
      final meters = dist * 1000;
      if (meters < 3) {
        headline = "Right beside you!";
      } else {
        headline = "${meters.toStringAsFixed(0)}m away";
      }
    } else if (dist < 0.01) {
      headline = "Right beside each other";
    } else {
      headline = '${_formatKm(dist)} away';
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: _proximityActive
            ? const LinearGradient(
                colors: [
                  Color(0xFF0D3A2F), // Glowing deep emerald green
                  Color(0xFF06251E), // Dark jade / black green
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [
                  Color(0xFF1E1716), // Dark rich chocolate
                  Color(0xFF261D1C), // Deep charcoal chocolate
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _proximityActive
              ? const Color(0xFF10B981).withValues(alpha: 0.20)
              : const Color(0xFFE8715A).withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _proximityActive
                ? const Color(0xFF10B981).withValues(alpha: 0.08)
                : const Color(0xFFE8715A).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Stack(
        children: [
          // Silent Ping Overlay / Refresh Trigger Button
          Positioned(
            top: 0,
            right: 0,
            child: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                : GestureDetector(
                    onTap: _forceRefresh,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.radar_rounded,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                    ),
                  ),
          ),
          
          GestureDetector(
            onTap: () {
              if (_proximityActive) {
                HapticFeedback.lightImpact();
              } else {
                _forceRefresh();
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // Direction Arrow Dial
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Radar ping pulse outer ring
                    if (_isRefreshing)
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 1.0, end: 1.4),
                        duration: const Duration(seconds: 1),
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: (1.4 - value).clamp(0.0, 1.0),
                            child: Container(
                              width: 90 * value,
                              height: 90 * value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.primary.withValues(alpha: 0.4),
                                  width: 2,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    // Neat rotating Arrow
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.25),
                        border: Border.all(
                          color: _proximityActive
                              ? const Color(0xFF10B981).withValues(alpha: 0.20)
                              : Colors.white.withValues(alpha: 0.08),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_proximityActive) ...[
                            // Concentric scanning circles
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.08),
                                  width: 1,
                                ),
                              ),
                            ),
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.05),
                                  width: 1,
                                ),
                              ),
                            ),
                          ],
                          Center(
                            child: (_proximityActive && dist != null && (dist * 1000) < 6)
                                ? ScaleTransition(
                                    scale: Tween<double>(begin: 0.95, end: 1.15).animate(
                                      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Opacity(
                                          opacity: 0.25,
                                          child: Icon(
                                            Icons.favorite_rounded,
                                            color: const Color(0xFF10B981),
                                            size: 46,
                                          ),
                                        ),
                                        Icon(
                                          Icons.favorite_rounded,
                                          color: const Color(0xFF10B981),
                                          size: 36,
                                        ),
                                      ],
                                    ),
                                  )
                                : AnimatedRotation(
                                    turns: _turns,
                                    duration: Duration(milliseconds: _proximityActive ? 50 : 300),
                                    curve: Curves.easeOutCubic,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Subtle background glow arrow
                                        Opacity(
                                          opacity: 0.25,
                                          child: Transform.translate(
                                            offset: const Offset(0, -1),
                                            child: Icon(
                                              Icons.navigation_rounded,
                                              color: _proximityActive ? const Color(0xFF10B981) : AppTheme.primary,
                                              size: 46,
                                            ),
                                          ),
                                        ),
                                        // Primary arrow
                                        Icon(
                                          Icons.navigation_rounded,
                                          color: _proximityActive ? const Color(0xFF10B981) : AppTheme.primary,
                                          size: 36,
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(width: 20),
                
                // Spatial & Connection Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _proximityActive ? const Color(0xFF10B981) : (partnerOnline ? Colors.green : Colors.transparent),
                              shape: BoxShape.circle,
                              boxShadow: (_proximityActive || partnerOnline)
                                  ? [
                                      BoxShadow(
                                        color: (_proximityActive ? const Color(0xFF10B981) : Colors.green).withValues(alpha: 0.8),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                          if (_proximityActive || partnerOnline) const SizedBox(width: 6),
                          Text(
                            _proximityActive ? 'RADAR ACTIVE' : (partnerOnline ? 'ACTIVE NOW' : 'TETHERED'),
                            style: GoogleFonts.dmSans(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              color: _proximityActive
                                  ? const Color(0xFF10B981)
                                  : (partnerOnline
                                      ? Colors.green
                                      : AppTheme.primary.withValues(alpha: 0.7)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        headline,
                        style: GoogleFonts.playfairDisplay(
                          color: Colors.white,
                          fontSize: headline.length > 18 ? 20 : 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (locality != null && dist != null && dist >= 0.01) ...[
                        const SizedBox(height: 2),
                        Text(
                          locality,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Battery Indicator
                          if (partnerBattery != null) ...[
                            Builder(
                              builder: (context) {
                                final level = partnerBattery['level'] as int? ?? -1;
                                final isCharging = partnerBattery['isCharging'] as bool? ?? false;
                                
                                IconData batteryIcon;
                                if (level >= 90) {
                                  batteryIcon = Icons.battery_full_rounded;
                                } else if (level >= 60) {
                                  batteryIcon = Icons.battery_5_bar_rounded;
                                } else if (level >= 30) {
                                  batteryIcon = Icons.battery_3_bar_rounded;
                                } else {
                                  batteryIcon = Icons.battery_alert_rounded;
                                }

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        batteryIcon,
                                        size: 14,
                                        color: level < 20 
                                            ? Colors.redAccent 
                                            : isCharging 
                                                ? Colors.green 
                                                : Colors.white70,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$level%${isCharging ? ' ⚡' : ''}',
                                        style: GoogleFonts.dmSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            ),
                          ],
                          
                          if (partnerMusic != null && partnerMusic['isPlaying'] == true) ...[
                            const SizedBox(width: 8),
                            // Music Sync Indicator
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.music_note_rounded,
                                      size: 14,
                                      color: AppTheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        partnerMusic['track'] ?? 'Listening...',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildPokeCard() {
    final myUid = _auth.currentUser?.uid;
    final isLastPokedByMe = _lastPokeFrom == myUid;

    String bannerText;
    if (_pokeCooldown) {
      bannerText = 'You have poked them';
    } else if (isLastPokedByMe) {
      bannerText = 'You poked ${_auth.partnerName}! Poke again? 💕';
    } else {
      bannerText = 'Let them know you\'re thinking of them';
    }

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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _pokeCooldown ? AppTheme.textMuted : null,
                        )),
                const SizedBox(height: 4),
                Text(
                  bannerText,
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
              onTap: _pokeCooldown ? null : _sendPoke,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _pokeCooldown
                      ? AppTheme.divider.withValues(alpha: 0.2)
                      : AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.touch_app_rounded,
                  color: _pokeCooldown ? AppTheme.textMuted : AppTheme.primary,
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

  // ── Music Card & Dialogs ───────────────────────────────────────────────────

  Widget _buildMusicCard() {
    final partnerMusic = _auth.isRay ? _aprooMusic : _rayMusic;
    final myMusic = _auth.isRay ? _rayMusic : _aprooMusic;
    final partnerName = _auth.partnerName;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.music_note_rounded,
                    color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Now Playing',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (partnerMusic != null && partnerMusic['isPlaying'] == true) ...[
            Row(
              children: [
                _RotatingVinyl(isPlaying: true),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        partnerMusic['track'] ?? 'Unknown Track',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'by ${partnerMusic['artist'] ?? 'Unknown Artist'}',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      const _AudioVisualizer(),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                const _RotatingVinyl(isPlaying: false),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '$partnerName isn\'t listening to music right now.',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: AppTheme.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: AppTheme.divider, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: myMusic != null && myMusic['isPlaying'] == true
                    ? Row(
                        children: [
                          const Icon(Icons.radio_button_checked_rounded,
                              color: Colors.green, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Sharing: "${myMusic['track']}"',
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'Let $partnerName know what you\'re playing!',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                        ),
                      ),
              ),
              if (myMusic != null && myMusic['isPlaying'] == true)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    MusicSyncService.clearMusic();
                  },
                  icon: const Icon(Icons.clear_rounded, size: 14, color: AppTheme.primary),
                  label: const Text(
                    'Stop',
                    style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold),
                  ),
                )
              else
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _showManualMusicDialog,
                  icon: const Icon(Icons.share_rounded, size: 14, color: AppTheme.primary),
                  label: const Text(
                    'Share',
                    style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: AppTheme.divider, height: 1),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_rounded, size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Syncs automatically with Spotify, YT Music & Apple Music! For Spotify, ensure "Device Broadcast Status" is enabled in Spotify Settings.',
                    style: GoogleFonts.dmSans(
                      fontSize: 10.5,
                      color: AppTheme.textMuted,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showManualMusicDialog() {
    final trackCtrl = TextEditingController();
    final artistCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.share_rounded,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Share song'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'What song are you listening to right now? It will appear on your partner\'s home screen.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: trackCtrl,
              decoration: const InputDecoration(
                hintText: 'Song title (e.g. Blinding Lights)',
                labelText: 'Song title',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: artistCtrl,
              decoration: const InputDecoration(
                hintText: 'Artist name (e.g. The Weeknd)',
                labelText: 'Artist',
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final track = trackCtrl.text.trim();
              final artist = artistCtrl.text.trim();
              if (track.isNotEmpty && artist.isNotEmpty) {
                HapticFeedback.mediumImpact();
                MusicSyncService.updateMusicManually(track, artist);
                Navigator.pop(context);
              }
            },
            child: const Text('Share Now'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddNoteTile(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _showAddNoteSheet();
      },
      child: Container(
        width: 85,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.2),
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add Note',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sticky Notes Board & Sheets ────────────────────────────────────────────

  Widget _buildStickyNotesBoard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stickyNotesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const SizedBox(
            height: 155,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final docs = (snapshot.data?.docs ?? []).where((d) {
          final data = d.data();
          return data['isArchived'] != true;
        }).toList();
        return SizedBox(
          height: 155,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: docs.length + 1,
            itemBuilder: (context, index) {
              if (index == docs.length) {
                return _buildAddNoteTile(context);
              }
              final doc = docs[index];
              final id = doc.id;
              final text = doc['text'] as String? ?? '';
              final colorIdx = doc['colorIndex'] as int? ?? 0;
              final author = doc['createdByName'] as String? ?? 'Partner';
              final authorUid = doc['createdBy'] as String? ?? '';
              final date = (doc['createdAt'] as Timestamp?)?.toDate();

              return _StickyNoteTile(
                id: id,
                text: text,
                colorIndex: colorIdx,
                author: author,
                isMe: authorUid == _auth.currentUser!.uid,
                date: date,
                onDelete: () => _confirmArchiveNote(id),
              );
            },
          ),
        );
      },
    );
  }

  void _showAddNoteSheet() {
    final textCtrl = TextEditingController();
    int selectedColor = 0;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pin a Sticky Note',
                    style: GoogleFonts.dmSans(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _StickyNoteTile._pastels[selectedColor],
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: textCtrl,
                  maxLines: 4,
                  maxLength: 90,
                  style: GoogleFonts.caveat(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2E2421),
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Write something sweet...',
                    hintStyle: TextStyle(color: Colors.black26),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    counterText: '',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select note paper color',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_StickyNoteTile._pastels.length, (idx) {
                  final isSelected = selectedColor == idx;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setSheetState(() => selectedColor = idx);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _StickyNoteTile._pastels[idx],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : AppTheme.divider,
                          width: isSelected ? 2.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded, color: AppTheme.primary, size: 18)
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final text = textCtrl.text.trim();
                    if (text.isNotEmpty) {
                      HapticFeedback.mediumImpact();
                      _firestore.addStickyNote(
                        coupleId,
                        text,
                        _auth.currentUser!.uid,
                        _auth.myName,
                        selectedColor,
                      );
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Pin Note'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmArchiveNote(String noteId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Peel off note?'),
        content: const Text('This sticky note will be moved to the archive instead of deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              HapticFeedback.heavyImpact();
              _firestore.archiveStickyNote(coupleId, noteId);
              Navigator.pop(context);
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  void _showStickyArchiveSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scrollCtrl) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _stickyNotesStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final archived = snapshot.data!.docs.where((d) {
              final data = d.data();
              return data['isArchived'] == true;
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.archive_rounded, color: AppTheme.primary, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Sticky Memory Archive',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.divider),
                Expanded(
                  child: archived.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inventory_2_outlined, size: 48, color: AppTheme.textMuted),
                              const SizedBox(height: 12),
                              Text(
                                'No archived notes yet.',
                                style: GoogleFonts.dmSans(color: AppTheme.textMuted, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.0,
                          ),
                          itemCount: archived.length,
                          itemBuilder: (context, index) {
                            final doc = archived[index];
                            final id = doc.id;
                            final text = doc['text'] as String? ?? '';
                            final colorIdx = doc['colorIndex'] as int? ?? 0;
                            final author = doc['createdByName'] as String? ?? 'Partner';
                            final paperColor = _StickyNoteTile._pastels[colorIdx % _StickyNoteTile._pastels.length];

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: paperColor,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      text,
                                      style: GoogleFonts.dmSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textDark,
                                      ),
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'From $author',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textMuted,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GestureDetector(
                                            onTap: () async {
                                              HapticFeedback.mediumImpact();
                                              await _firestore.restoreStickyNote(coupleId, id);
                                            },
                                            child: const Icon(
                                              Icons.unarchive_rounded,
                                              size: 16,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () {
                                              HapticFeedback.heavyImpact();
                                              showDialog(
                                                context: ctx,
                                                builder: (_) => AlertDialog(
                                                  title: const Text('Delete permanently?'),
                                                  content: const Text('This will erase the sticky note memory forever.'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.pop(ctx),
                                                      child: const Text('Keep it'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () async {
                                                        Navigator.pop(ctx);
                                                        await _firestore.permanentlyDeleteStickyNote(coupleId, id);
                                                      },
                                                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                            child: const Icon(
                                              Icons.delete_forever_rounded,
                                              size: 16,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Rotating Vinyl Graphic ───────────────────────────────────────────────────

class _RotatingVinyl extends StatefulWidget {
  final bool isPlaying;
  const _RotatingVinyl({required this.isPlaying});

  @override
  State<_RotatingVinyl> createState() => _RotatingVinylState();
}

class _RotatingVinylState extends State<_RotatingVinyl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    if (widget.isPlaying) {
      _ctrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RotatingVinyl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying) {
      _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[900],
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          gradient: const RadialGradient(
            colors: [
              Color(0xFF333333),
              Color(0xFF111111),
            ],
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(4),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary,
            ),
            child: const Center(
              child: Icon(Icons.music_note_rounded, color: Colors.white, size: 10),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Audio Visualizer Bars ─────────────────────────────────────────────────────

class _AudioVisualizer extends StatefulWidget {
  const _AudioVisualizer();

  @override
  State<_AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<_AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<double> _heightMultiplier = [0.2, 0.8, 0.5, 0.9, 0.4, 0.7, 0.3];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(7, (index) {
            final phase = (index * 0.15);
            final value = ((_ctrl.value + phase) % 1.0);
            final height = 4.0 + (value * 16.0 * _heightMultiplier[index]);

            return Container(
              width: 3.5,
              height: height,
              margin: const EdgeInsets.only(right: 2.5),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Sticky Note Card Grid Tile ────────────────────────────────────────────────

class _StickyNoteTile extends StatelessWidget {
  final String id;
  final String text;
  final int colorIndex;
  final String author;
  final bool isMe;
  final DateTime? date;
  final VoidCallback onDelete;

  static const _pastels = [
    Color(0xFFFFF0EE),
    Color(0xFFFEF9C3),
    Color(0xFFF0FDF4),
    Color(0xFFEFF6FF),
    Color(0xFFFFF0F5),
  ];

  const _StickyNoteTile({
    required this.id,
    required this.text,
    required this.colorIndex,
    required this.author,
    required this.isMe,
    required this.date,
    required this.onDelete,
  });

  void _showReadNoteDialog(BuildContext context, Color paperColor) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
              decoration: BoxDecoration(
                color: paperColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(4, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Text(
                        text,
                        style: GoogleFonts.caveat(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF3E2D29),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '— $author',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF8C7A76),
                        ),
                      ),
                      if (date != null)
                        Builder(
                          builder: (context) {
                            final istDate = date!.toUtc().add(const Duration(hours: 5, minutes: 30));
                            return Text(
                              '${DateFormat('d MMMM y, h:mm a').format(istDate)} IST',
                              style: GoogleFonts.dmSans(
                                fontSize: 10,
                                color: const Color(0xFF8C7A76),
                              ),
                            );
                          }
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: -8,
              child: Container(
                width: 70,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 2,
                    )
                  ]
                ),
              ),
            ),
            Positioned(
              top: -12,
              right: -12,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      )
                    ]
                  ),
                  child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _pastels[colorIndex % _pastels.length];

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showReadNoteDialog(context, color);
      },
      onLongPress: () {
        HapticFeedback.heavyImpact();
        onDelete();
      },
      child: Container(
        width: 145,
        margin: const EdgeInsets.only(right: 14),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(2, 4),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -24,
                  left: 40,
                  child: Container(
                    width: 36,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          text,
                          style: GoogleFonts.caveat(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF3E2D29),
                            height: 1.25,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '— $author',
                            style: GoogleFonts.dmSans(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF8C7A76),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (date != null)
                          Builder(
                            builder: (context) {
                              final istDate = date!.toUtc().add(const Duration(hours: 5, minutes: 30));
                              return Text(
                                DateFormat('d MMM').format(istDate),
                                style: GoogleFonts.dmSans(
                                  fontSize: 9,
                                  color: const Color(0xFF8C7A76),
                                ),
                              );
                            }
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    }
