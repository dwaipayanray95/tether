import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static const _coupleId = 'ray-aproo';

  static Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  static Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }

  static Future<void> forceUpload(Position pos, String myKey, String myName) async {
    await FirebaseFirestore.instance
        .doc('couples/$_coupleId/locations/$myKey')
        .set({
      'lat': pos.latitude,
      'lng': pos.longitude,
      'updatedAt': FieldValue.serverTimestamp(),
      'name': myName,
    });
  }

  // Only writes to Firestore if moved >100m or >10 min since last upload
  static Future<void> updateIfNeeded(Position pos, String myKey, String myName) async {
    final prefs = await SharedPreferences.getInstance();
    final lastLat = prefs.getDouble('loc_lat_$myKey');
    final lastLng = prefs.getDouble('loc_lng_$myKey');
    final lastTime = prefs.getInt('loc_time_$myKey') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    bool shouldUpload = (now - lastTime) > 10 * 60 * 1000;

    if (lastLat != null && lastLng != null) {
      final dist = Geolocator.distanceBetween(
          lastLat, lastLng, pos.latitude, pos.longitude);
      if (dist > 100) shouldUpload = true;
    } else {
      shouldUpload = true;
    }

    if (shouldUpload) {
      await forceUpload(pos, myKey, myName);
      await prefs.setDouble('loc_lat_$myKey', pos.latitude);
      await prefs.setDouble('loc_lng_$myKey', pos.longitude);
      await prefs.setInt('loc_time_$myKey', now);
    }
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> locationStream(String key) {
    return FirebaseFirestore.instance
        .doc('couples/$_coupleId/locations/$key')
        .snapshots();
  }

  static Future<Map<String, dynamic>?> getLocation(String key) async {
    final snap = await FirebaseFirestore.instance
        .doc('couples/$_coupleId/locations/$key')
        .get();
    return snap.data();
  }
}
