import 'package:flutter/services.dart';
import 'log_service.dart';

/// Controls Android's PROXIMITY_SCREEN_OFF_WAKE_LOCK.
///
/// When acquired, Android automatically turns the screen off whenever the
/// proximity sensor detects something close (e.g. an ear) and turns it back
/// on when the object moves away — exactly like the built-in Phone app.
class ProximityService {
  static const _channel =
      MethodChannel('com.theawesomeray.tether/proximity');

  static Future<void> acquire() async {
    try {
      await _channel.invokeMethod('acquire');
      LogService.log('Proximity wake lock acquired');
    } catch (e) {
      LogService.log('ProximityService.acquire error: $e');
    }
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod('release');
      LogService.log('Proximity wake lock released');
    } catch (e) {
      LogService.log('ProximityService.release error: $e');
    }
  }
}
