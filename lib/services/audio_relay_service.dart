import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart';

class AudioRelayService {
  final _logger = Logger();
  final _db = FirebaseDatabase.instance;
  
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  
  StreamSubscription? _chunksSub;
  StreamController<Food>? _recordingStreamController;
  
  bool _isMuted = false;
  String? _currentCallId;

  Future<void> start(String callId, String myKey, String partnerKey) async {
    _currentCallId = callId;
    _logger.i('[AudioRelay] Starting for call: $callId');

    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();

    await _recorder!.openRecorder();
    await _player!.openPlayer();

    // 1. Setup Recording
    _recordingStreamController = StreamController<Food>();
    
    // We use opusOGG for high compression
    await _recorder!.startRecorder(
      toStream: _recordingStreamController!.sink,
      codec: Codec.opusOGG,
      sampleRate: 16000,
      bitRate: 16000,
      numChannels: 1,
    );

    _recordingStreamController!.stream.listen((food) {
      if (food is FoodData && food.data != null && !_isMuted) {
        _db.ref('audio_relay/$callId/$myKey/chunks').push().set({
          'd': base64Encode(food.data!),
          'ts': ServerValue.timestamp,
        });
      }
    });

    // 2. Setup Playback
    await _player!.startPlayerFromStream(
      codec: Codec.opusOGG,
      sampleRate: 16000,
      numChannels: 1,
    );

    _chunksSub = _db
        .ref('audio_relay/$callId/$partnerKey/chunks')
        .onChildAdded
        .listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && data['d'] != null) {
        final bytes = base64Decode(data['d'] as String);
        _player!.feedFromStream(bytes);
      }
    });
  }

  Future<void> stop() async {
    _logger.i('[AudioRelay] Stopping');
    
    await _chunksSub?.cancel();
    _chunksSub = null;
    
    if (_recorder != null) {
      await _recorder!.stopRecorder();
      await _recorder!.closeRecorder();
      _recorder = null;
    }
    
    if (_player != null) {
      await _player!.stopPlayer();
      await _player!.closePlayer();
      _player = null;
    }

    await _recordingStreamController?.close();
    _recordingStreamController = null;

    if (_currentCallId != null) {
      // Cleanup RTDB data for this call
      _db.ref('audio_relay/$_currentCallId').remove();
      _currentCallId = null;
    }
  }

  void setMuted(bool muted) {
    _isMuted = muted;
    _logger.i('[AudioRelay] Mute set to: $muted');
  }

  Future<void> setSpeakerOn(bool speakerOn) async {
    if (_player != null) {
      await _player!.setSpeakerphoneOn(speakerOn);
      _logger.i('[AudioRelay] Speaker set to: $speakerOn');
    }
  }
}
