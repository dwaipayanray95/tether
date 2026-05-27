import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'log_service.dart';

class MusicSyncService {
  static const _channel = MethodChannel('com.theawesomeray.tether/music');
  static final _firestore = FirestoreService();
  
  static String? _lastTrack;
  static String? _lastArtist;
  static bool? _lastIsPlaying;

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onMusicChanged') {
        final data = Map<String, dynamic>.from(call.arguments);
        final track = data['track'] as String? ?? '';
        final artist = data['artist'] as String? ?? '';
        final album = data['album'] as String? ?? '';
        final isPlaying = data['isPlaying'] as bool? ?? false;

        // Skip writing if identical to last state
        if (track == _lastTrack && artist == _lastArtist && isPlaying == _lastIsPlaying) {
          return;
        }

        _lastTrack = track;
        _lastArtist = artist;
        _lastIsPlaying = isPlaying;

        final myUid = FirebaseAuth.instance.currentUser?.uid;
        if (myUid == null) return;

        // Check allowedEmails mapping dynamically
        final email = FirebaseAuth.instance.currentUser?.email;
        final key = email == 'ray@redacted.invalid' ? 'ray' : 'aproo';

        LogService.log('[MusicSync] Received Native Broadcast: "$track" by $artist (Playing: $isPlaying)');

        if (!isPlaying || track.isEmpty) {
          await _firestore.updateMusicPresence(key, null);
        } else {
          await _firestore.updateMusicPresence(key, {
            'track': track,
            'artist': artist,
            'album': album,
            'isPlaying': true,
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
      }
    });
  }

  static Future<void> updateMusicManually(String track, String artist) async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;
    final key = email == 'ray@redacted.invalid' ? 'ray' : 'aproo';

    LogService.log('[MusicSync] Setting manual track: "$track" by $artist');
    
    _lastTrack = track;
    _lastArtist = artist;
    _lastIsPlaying = true;

    await _firestore.updateMusicPresence(key, {
      'track': track,
      'artist': artist,
      'album': 'Shared manually',
      'isPlaying': true,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> clearMusic() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;
    final key = email == 'ray@redacted.invalid' ? 'ray' : 'aproo';

    LogService.log('[MusicSync] Clearing active music track');
    _lastTrack = null;
    _lastArtist = null;
    _lastIsPlaying = null;

    await _firestore.updateMusicPresence(key, null);
  }
}
