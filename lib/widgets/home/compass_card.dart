import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';

class CompassCard extends StatefulWidget {
  const CompassCard({super.key});

  @override
  State<CompassCard> createState() => _CompassCardState();
}

class _CompassCardState extends State<CompassCard>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  final _firestore = FirestoreService();
  final _rtdb = FirebaseDatabase.instance;

  // Compass sensor
  static const _compassChannel =
      EventChannel('com.theawesomeray.tether/compass');
  StreamSubscription? _compassSub;
  double _deviceHeading = 0.0;
  double _lastTargetDegrees = 0.0;
  double _turns = 0.0;

  // Location
  Position? _myPosition;
  Map<String, dynamic>? _partnerLocation;
  bool _locationLoading = true;
  bool _isRefreshing = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _partnerLocSub;

  // Presence (for battery / music / online status)
  Map<String, dynamic>? _rayPresence;
  Map<String, dynamic>? _aprooPresence;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _presenceSub;

  // Proximity radar (RTDB 3Hz)
  StreamSubscription? _rtdbProximitySub;
  StreamSubscription? _partnerRadarActiveSub;
  StreamSubscription<Position>? _myPositionSub;
  Timer? _rtdbProximityTimer;
  bool _proximityActive = false;
  bool _partnerRadarActive = false;
  double? _radarPartnerLat;
  double? _radarPartnerLng;

  // Pulse animation (used for the heart at < 6m)
  late AnimationController _pulseController;

  // ── Helpers ──────────────────────────────────────────────────────────────

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
    return Geolocator.distanceBetween(
            my.latitude, my.longitude, plat, plng) /
        1000;
  }

  double _calculateBearing(
      double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final lat1Rad = lat1 * (math.pi / 180.0);
    final lat2Rad = lat2 * (math.pi / 180.0);
    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);
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

  String _formatKm(double km) {
    final rounded = km.round();
    if (rounded >= 1000) {
      final s = rounded.toString();
      final insert = s.length - 3;
      return '${s.substring(0, insert)},${s.substring(insert)} kms';
    }
    return '$rounded kms';
  }

  // ── Init / Dispose ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      _initCompass();
    });

    _initPresence();

    final partnerKey = _auth.isRay ? 'aproo' : 'ray';
    _partnerRadarActiveSub = _rtdb
        .ref('proximity_sync/ray-aproo/$partnerKey/active')
        .onValue
        .listen((event) {
      final active = event.snapshot.value as bool? ?? false;
      if (mounted) {
        setState(() => _partnerRadarActive = active);
        _checkProximityRadar();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _compassSub?.cancel();
    _partnerLocSub?.cancel();
    _presenceSub?.cancel();
    _rtdbProximitySub?.cancel();
    _partnerRadarActiveSub?.cancel();
    _myPositionSub?.cancel();
    _rtdbProximityTimer?.cancel();
    super.dispose();
  }

  // ── Compass ───────────────────────────────────────────────────────────────

  void _initCompass() {
    try {
      _compassSub =
          _compassChannel.receiveBroadcastStream().listen((event) {
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

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    final hasPermission = await LocationService.requestPermission();
    if (!hasPermission) {
      if (mounted) setState(() => _locationLoading = false);
      return;
    }

    final myKey = _auth.isRay ? 'ray' : 'aproo';
    final partnerKey = _auth.isRay ? 'aproo' : 'ray';

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

    _partnerLocSub =
        LocationService.locationStream(partnerKey).listen((snap) {
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

    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _isRefreshing) {
        setState(() => _isRefreshing = false);
      }
    });
  }

  // ── Presence ──────────────────────────────────────────────────────────────

  void _initPresence() {
    _presenceSub = _firestore.presenceStream().listen((snap) {
      final data = snap.data();
      if (mounted && data != null) {
        setState(() {
          final r = data['ray'] as Map<String, dynamic>?;
          final a = data['aproo'] as Map<String, dynamic>?;
          _rayPresence = r;
          _aprooPresence = a;
        });
      }
    });
  }

  // ── Proximity Radar ───────────────────────────────────────────────────────

  void _checkProximityRadar() {
    final dist = _distanceKm;
    final shouldBeActive = (dist != null && dist <= 0.15) || _partnerRadarActive;
    if (shouldBeActive && !_proximityActive) {
      _startProximityRadar();
    } else if (!shouldBeActive && _proximityActive) {
      _stopProximityRadar();
    }
  }

  void _startProximityRadar() {
    if (_proximityActive) return;
    debugPrint('Starting Proximity Radar (3Hz RTDB mode)...');
    final partnerKey = _auth.isRay ? 'aproo' : 'ray';
    final myKey = _auth.isRay ? 'ray' : 'aproo';

    setState(() => _proximityActive = true);

    _rtdbProximitySub =
        _rtdb.ref('proximity_sync/ray-aproo/$partnerKey').onValue.listen((event) {
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

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );
    _myPositionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      if (mounted) {
        setState(() {
          _myPosition = pos;
          _updateTurns(_getRotationTarget());
        });
        _checkProximityRadar();
      }
    });

    _rtdbProximityTimer =
        Timer.periodic(const Duration(milliseconds: 333), (timer) async {
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dist = _distanceKm;
    final locality = _partnerLocation?['locality'] as String?;

    final partnerPresence = _auth.isRay ? _aprooPresence : _rayPresence;
    final partnerLastSeenRaw = partnerPresence?['lastSeen'];
    final partnerLastSeen = partnerLastSeenRaw is Timestamp
        ? partnerLastSeenRaw
        : null;
    final partnerOnline = partnerLastSeen != null &&
        DateTime.now().difference(partnerLastSeen.toDate()).inMinutes < 1;

    final partnerBattery = partnerPresence?['battery'] != null
        ? Map<String, dynamic>.from(partnerPresence!['battery'] as Map)
        : null;
    final partnerMusic = partnerPresence?['music'] != null
        ? Map<String, dynamic>.from(partnerPresence!['music'] as Map)
        : null;

    String headline;
    if (_locationLoading && _partnerLocation == null) {
      headline = 'Searching...';
    } else if (dist == null) {
      headline = 'Waiting for ${_auth.partnerDisplayName}';
    } else if (_proximityActive) {
      final meters = dist * 1000;
      if (meters < 3) {
        headline = 'Right beside you!';
      } else {
        headline = '${meters.toStringAsFixed(0)}m away';
      }
    } else if (dist < 0.01) {
      headline = 'Right beside each other';
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
                colors: [Color(0xFF0D3A2F), Color(0xFF06251E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF1E1716), Color(0xFF261D1C)],
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
          // Refresh / Radar ping button
          Positioned(
            top: 0,
            right: 0,
            child: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary),
                  )
                : GestureDetector(
                    onTap: _forceRefresh,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.radar_rounded,
                          color: AppTheme.primary, size: 20),
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
                // ── Direction dial ──────────────────────────────────────
                Stack(
                  alignment: Alignment.center,
                  children: [
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
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.08),
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
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.05),
                                  width: 1,
                                ),
                              ),
                            ),
                          ],
                          Center(
                            child: (_proximityActive &&
                                    dist != null &&
                                    (dist * 1000) < 6)
                                ? ScaleTransition(
                                    scale: Tween<double>(
                                            begin: 0.95, end: 1.15)
                                        .animate(CurvedAnimation(
                                      parent: _pulseController,
                                      curve: Curves.easeInOut,
                                    )),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Opacity(
                                          opacity: 0.25,
                                          child: Icon(Icons.favorite_rounded,
                                              color: const Color(0xFF10B981),
                                              size: 46),
                                        ),
                                        const Icon(Icons.favorite_rounded,
                                            color: Color(0xFF10B981), size: 36),
                                      ],
                                    ),
                                  )
                                : AnimatedRotation(
                                    turns: _turns,
                                    duration: Duration(
                                        milliseconds:
                                            _proximityActive ? 50 : 300),
                                    curve: Curves.easeOutCubic,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Opacity(
                                          opacity: 0.25,
                                          child: Transform.translate(
                                            offset: const Offset(0, -1),
                                            child: Icon(
                                              Icons.navigation_rounded,
                                              color: _proximityActive
                                                  ? const Color(0xFF10B981)
                                                  : AppTheme.primary,
                                              size: 46,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.navigation_rounded,
                                          color: _proximityActive
                                              ? const Color(0xFF10B981)
                                              : AppTheme.primary,
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

                // ── Spatial details ─────────────────────────────────────
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
                              color: _proximityActive
                                  ? const Color(0xFF10B981)
                                  : (partnerOnline
                                      ? Colors.green
                                      : Colors.transparent),
                              shape: BoxShape.circle,
                              boxShadow: (_proximityActive || partnerOnline)
                                  ? [
                                      BoxShadow(
                                        color: (_proximityActive
                                                ? const Color(0xFF10B981)
                                                : Colors.green)
                                            .withValues(alpha: 0.8),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                          if (_proximityActive || partnerOnline)
                            const SizedBox(width: 6),
                          Text(
                            _proximityActive
                                ? 'RADAR ACTIVE'
                                : (partnerOnline ? 'ACTIVE NOW' : 'TETHERED'),
                            style: GoogleFonts.dmSans(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              color: _proximityActive
                                  ? const Color(0xFF10B981)
                                  : (partnerOnline
                                      ? Colors.green
                                      : AppTheme.primary
                                          .withValues(alpha: 0.7)),
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
                          // Battery chip
                          if (partnerBattery != null) ...[
                            Builder(builder: (context) {
                              final level =
                                  partnerBattery['level'] as int? ?? -1;
                              final isCharging =
                                  partnerBattery['isCharging'] as bool? ??
                                      false;
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(batteryIcon,
                                        size: 14,
                                        color: level < 20
                                            ? Colors.redAccent
                                            : isCharging
                                                ? Colors.green
                                                : Colors.white70),
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
                            }),
                          ],
                          // Music chip
                          if (partnerMusic != null &&
                              partnerMusic['isPlaying'] == true) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.music_note_rounded,
                                        size: 14, color: AppTheme.primary),
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
}
