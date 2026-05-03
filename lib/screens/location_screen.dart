import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/location_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final _auth = AuthService();
  GoogleMapController? _mapController;

  Set<Marker> _markers = {};
  LatLng? _myPosition;
  LatLng? _partnerPosition;
  DateTime? _partnerUpdatedAt;
  DateTime? _myUpdatedAt;
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;

  StreamSubscription? _partnerSub;
  StreamSubscription? _mySub;
  Timer? _locationTimer;

  late String _myKey;
  late String _partnerKey;

  @override
  void initState() {
    super.initState();
    _myKey = _auth.myName.toLowerCase();
    _partnerKey = _auth.partnerName.toLowerCase();
    _init();
  }

  Future<void> _init() async {
    final granted = await LocationService.requestPermission();
    if (!granted) {
      setState(() {
        _loading = false;
        _errorMessage = 'Location permission denied. Please enable it in Settings.';
      });
      return;
    }

    await _uploadMyLocation();

    _partnerSub = LocationService.locationStream(_partnerKey).listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;
      final ts = data['updatedAt'] as Timestamp?;
      setState(() {
        _partnerPosition = LatLng(
          (data['lat'] as num).toDouble(),
          (data['lng'] as num).toDouble(),
        );
        _partnerUpdatedAt = ts?.toDate();
        _rebuildMarkers();
        _loading = false;
      });
    });

    _mySub = LocationService.locationStream(_myKey).listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data()!;
      final ts = data['updatedAt'] as Timestamp?;
      setState(() {
        _myPosition = LatLng(
          (data['lat'] as num).toDouble(),
          (data['lng'] as num).toDouble(),
        );
        _myUpdatedAt = ts?.toDate();
        _rebuildMarkers();
        _loading = false;
      });
    });

    // Refresh my location every 2 minutes while screen is open
    _locationTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _uploadMyLocation(),
    );
  }

  Future<void> _uploadMyLocation({bool force = false}) async {
    final pos = await LocationService.getCurrentPosition();
    if (pos == null) return;
    if (force) {
      await LocationService.forceUpload(pos, _myKey, _auth.myName);
    } else {
      await LocationService.updateIfNeeded(pos, _myKey, _auth.myName);
    }
  }

  void _rebuildMarkers() {
    final markers = <Marker>{};
    if (_myPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: _myPosition!,
        infoWindow: InfoWindow(title: _auth.myName, snippet: 'You'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
      ));
    }
    if (_partnerPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('partner'),
        position: _partnerPosition!,
        infoWindow: InfoWindow(title: _auth.partnerName),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      ));
    }
    _markers = markers;
  }

  void _fitBoth() {
    if (_mapController == null || _myPosition == null || _partnerPosition == null) return;
    final sw = LatLng(
      [_myPosition!.latitude, _partnerPosition!.latitude].reduce((a, b) => a < b ? a : b),
      [_myPosition!.longitude, _partnerPosition!.longitude].reduce((a, b) => a < b ? a : b),
    );
    final ne = LatLng(
      [_myPosition!.latitude, _partnerPosition!.latitude].reduce((a, b) => a > b ? a : b),
      [_myPosition!.longitude, _partnerPosition!.longitude].reduce((a, b) => a > b ? a : b),
    );
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 80),
    );
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await _uploadMyLocation(force: true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() => _refreshing = false);
      if (_myPosition != null && _partnerPosition != null) _fitBoth();
    }
  }

  @override
  void dispose() {
    _partnerSub?.cancel();
    _mySub?.cancel();
    _locationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = _myPosition ??
        _partnerPosition ??
        const LatLng(20.5937, 78.9629);

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: initialTarget, zoom: 14),
            markers: _markers,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              if (_myPosition != null && _partnerPosition != null) {
                Future.delayed(const Duration(milliseconds: 600), _fitBoth);
              }
            },
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _mapButton(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                  const SizedBox(width: 10),
                  _mapButton(
                    child: Text('Location',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const Spacer(),
                  if (_myPosition != null && _partnerPosition != null)
                    _mapButton(
                      onTap: _fitBoth,
                      child: const Icon(Icons.fit_screen_rounded, size: 20),
                    ),
                ],
              ),
            ),
          ),

          // Loading
          if (_loading)
            const ColoredBox(
              color: Colors.white54,
              child: Center(child: CircularProgressIndicator()),
            ),

          // Error
          if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textMuted)),
              ),
            ),

          // Bottom card
          if (!_loading && _errorMessage == null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 16,
                        offset: Offset(0, 4))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _locationChip(
                          name: _auth.partnerName,
                          updatedAt: _partnerUpdatedAt,
                          color: AppTheme.secondary,
                          hasLocation: _partnerPosition != null,
                        ),
                        const SizedBox(width: 12),
                        _locationChip(
                          name: _auth.myName,
                          updatedAt: _myUpdatedAt,
                          color: AppTheme.primary,
                          hasLocation: _myPosition != null,
                          isMe: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _refreshing ? null : _refresh,
                        icon: _refreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.my_location_rounded, size: 18),
                        label: Text(
                            _refreshing ? 'Updating...' : 'Share my location now'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mapButton({VoidCallback? onTap, required Widget child}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: child,
      ),
    );
  }

  Widget _locationChip({
    required String name,
    required DateTime? updatedAt,
    required Color color,
    required bool hasLocation,
    bool isMe = false,
  }) {
    final String subtitle;
    if (!hasLocation) {
      subtitle = 'No location yet';
    } else if (isMe) {
      subtitle = updatedAt != null ? 'Updated ${timeago.format(updatedAt)}' : 'Your location';
    } else {
      subtitle = updatedAt != null ? timeago.format(updatedAt) : 'Location available';
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppTheme.textDark)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
