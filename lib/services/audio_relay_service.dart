import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:opus_dart/opus_dart.dart';

import 'log_service.dart';

/// Bidirectional voice relay via Firebase Realtime Database.
///
/// Sender:  Mic -> PCM16 (flutter_sound) -> StreamOpusEncoder (20ms/VoIP)
///              -> base64 -> RTDB push (~2 KB/s at ~16 kbps)
/// Receiver: RTDB onChildAdded -> StreamOpusDecoder -> PCM16
///              -> feedUint8FromStream -> hardware speaker
class AudioRelayService {
  static const _channel = MethodChannel('com.theawesomeray.tether/proximity');

  final _db = FirebaseDatabase.instance;

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;

  /// Raw PCM16 bytes from the microphone (Codec.pcm16).
  StreamController<Uint8List>? _recordingController;

  /// Opus packets from RTDB, piped into the decoder.
  StreamController<Uint8List>? _opusInputController;

  StreamSubscription<void>? _encoderSub;
  StreamSubscription<void>? _decoderSub;
  StreamSubscription<void>? _chunksSub;

  bool _isMuted = false;
  String? _currentCallId;

  // ── Start ─────────────────────────────────────────────────────────────────

  Future<void> start(String callId, String myKey, String partnerKey) async {
    _currentCallId = callId;
    LogService.log('[AudioRelay] Starting for call: $callId');

    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();

    await _recorder!.openRecorder();
    await _player!.openPlayer();

    // ── Playback: RTDB Opus → decode → PCM16 → hardware ─────────────────────

    await _player!.startPlayerFromStream(
      codec: Codec.pcm16,
      sampleRate: 16000,
      numChannels: 1,
      bufferSize: 8192,
      interleaved: true,
    );

    _opusInputController = StreamController<Uint8List>();

    // StreamOpusDecoder.bytes: Stream<Uint8List?> → Stream<List<num>>
    // copyOutput:true guarantees the output is a Uint8List in memory → safe cast
    _decoderSub = _opusInputController!.stream
        .cast<Uint8List?>()
        .transform(StreamOpusDecoder.bytes(
          floatOutput: false,
          sampleRate: 16000,
          channels: 1,
          copyOutput: true,
          forwardErrorCorrection: false,
        ))
        .cast<Uint8List>()
        .listen(
          (Uint8List pcmBytes) => _player?.feedUint8FromStream(pcmBytes),
          onError: (Object e) => LogService.log('[AudioRelay] Decoder error: $e'),
        );

    // Listen for partner Opus packets from RTDB
    _chunksSub = _db
        .ref('audio_relay/$callId/$partnerKey/chunks')
        .onChildAdded
        .listen((DatabaseEvent event) {
      final data = event.snapshot.value as Map?;
      if (data != null && data['d'] != null) {
        final opusBytes = base64Decode(data['d'] as String);
        if (!(_opusInputController?.isClosed ?? true)) {
          _opusInputController!.add(Uint8List.fromList(opusBytes));
          LogService.log('[AudioRelay] Playing chunk');
        }
      }
    }, onError: (Object e) => LogService.log('[AudioRelay] RTDB error: $e'));

    // ── Recording: mic → PCM16 → encode → RTDB ──────────────────────────────

    _recordingController = StreamController<Uint8List>();

    // StreamOpusEncoder.bytes: Stream<List<int>> → Stream<Uint8List>
    // Uint8List is-a List<int>, so cast<List<int>>() is a safe runtime cast
    _encoderSub = _recordingController!.stream
        .cast<List<int>>()
        .transform(StreamOpusEncoder.bytes(
          floatInput: false,
          frameTime: FrameTime.ms20,
          sampleRate: 16000,
          channels: 1,
          application: Application.voip,
          copyOutput: true,
          fillUpLastFrame: false,
        ))
        .listen(
          (Uint8List opusPacket) {
            if (!_isMuted) {
              LogService.log('[AudioRelay] Writing chunk');
              _db.ref('audio_relay/$callId/$myKey/chunks').push().set({
                'd': base64Encode(opusPacket),
                'ts': ServerValue.timestamp,
              });
            }
          },
          onError: (Object e) => LogService.log('[AudioRelay] Encoder error: $e'),
        );

    await _recorder!.startRecorder(
      toStream: _recordingController!.sink,
      codec: Codec.pcm16,
      sampleRate: 16000,
      numChannels: 1,
    );

    LogService.log('[AudioRelay] Started — recording and playback active');
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    LogService.log('[AudioRelay] Stopping');

    if (_recorder != null) {
      try {
        await _recorder!.stopRecorder();
        await _recorder!.closeRecorder();
      } catch (e) {
        LogService.log('[AudioRelay] Recorder stop error: $e');
      }
      _recorder = null;
    }

    await _encoderSub?.cancel();
    _encoderSub = null;
    if (!(_recordingController?.isClosed ?? true)) {
      await _recordingController!.close();
    }
    _recordingController = null;

    await _chunksSub?.cancel();
    _chunksSub = null;

    if (!(_opusInputController?.isClosed ?? true)) {
      await _opusInputController!.close();
    }
    _opusInputController = null;

    await _decoderSub?.cancel();
    _decoderSub = null;

    if (_player != null) {
      try {
        await _player!.stopPlayer();
        await _player!.closePlayer();
      } catch (e) {
        LogService.log('[AudioRelay] Player stop error: $e');
      }
      _player = null;
    }

    if (_currentCallId != null) {
      try {
        await _db.ref('audio_relay/$_currentCallId').remove();
      } catch (e) {
        LogService.log('[AudioRelay] RTDB cleanup error: $e');
      }
      _currentCallId = null;
    }

    LogService.log('[AudioRelay] Stopped');
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  void setMuted(bool muted) {
    _isMuted = muted;
    LogService.log('[AudioRelay] Mute: $muted');
  }

  Future<void> setSpeakerOn(bool on) async {
    LogService.log('[AudioRelay] Speaker: $on');
    try {
      await _channel.invokeMethod('setSpeakerOn', on);
    } catch (e) {
      LogService.log('[AudioRelay] setSpeakerOn error: $e');
    }
  }
}
