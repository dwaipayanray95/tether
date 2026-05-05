import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fcm_service.dart';

class LocationService {
  static const _coupleId = 'raayyy-aproo';

  static Future<String?> getLocality(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        return p.locality ?? p.subLocality ?? p.name;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    // If user granted "While in Use", try to request "Always" for background updates
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || 
        permission == LocationPermission.deniedForever) {
      return false;
    }

    // Request precise location if it is reduced
    final accuracy = await Geolocator.getLocationAccuracy();
    if (accuracy == LocationAccuracyStatus.reduced) {
      await Geolocator.requestTemporaryFullAccuracy(
        purposeKey: 'PreciseLocation',
      );
    }

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
    final locality = await getLocality(pos.latitude, pos.longitude);
    await FirebaseFirestore.instance
        .doc('couples/$_coupleId/locations/$myKey')
        .set({
      'lat': pos.latitude,
      'lng': pos.longitude,
      'locality': locality,
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
    final lastLocality = prefs.getString('loc_locality_$myKey');
    final now = DateTime.now().millisecondsSinceEpoch;

    bool shouldUpload = (now - lastTime) > 10 * 60 * 1000;

    if (lastLat != null && lastLng != null) {
      final dist = Geolocator.distanceBetween(
          lastLat, lastLng, pos.latitude, pos.longitude);
      if (dist > 100) shouldUpload = true;
    } else {
      shouldUpload = true;
    }
    
    // Also upload if locality is missing (new feature)
    if (lastLocality == null) shouldUpload = true;

    if (shouldUpload) {
      final locality = await getLocality(pos.latitude, pos.longitude);
      await FirebaseFirestore.instance
          .doc('couples/$_coupleId/locations/$myKey')
          .set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'locality': locality,
        'updatedAt': FieldValue.serverTimestamp(),
        'name': myName,
      });
      await prefs.setDouble('loc_lat_$myKey', pos.latitude);
      await prefs.setDouble('loc_lng_$myKey', pos.longitude);
      await prefs.setInt('loc_time_$myKey', now);
      if (locality != null) await prefs.setString('loc_locality_$myKey', locality);
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

  static Future<void> pingPartner(String myName) async {
    final partnerName = myName == 'Raayyy' ? 'aproo' : 'raayyy';
    await FcmService.send(
      partnerName: partnerName,
      title: '📍 $myName is checking in!',
      body: 'Your location has been shared with $myName',
      type: 'ping',
    );
  }
}
