import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'log_service.dart';

/// Wraps a single WebRTC peer connection for a voice call.
/// Video tracks are not created here — audio only.
class WebRtcService {
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      // TURN relay — each URL as a separate object for maximum compatibility
      {'urls': 'turn:openrelay.metered.ca:80',               'username': 'openrelayproject', 'credential': 'openrelayproject'},
      {'urls': 'turn:openrelay.metered.ca:443',              'username': 'openrelayproject', 'credential': 'openrelayproject'},
      {'urls': 'turn:openrelay.metered.ca:443?transport=tcp', 'username': 'openrelayproject', 'credential': 'openrelayproject'},
    ],
    // Pre-gather candidates (incl. TURN) before negotiation starts so relay
    // candidates are ready the instant ICE checking begins — prevents the
    // agent from failing before TURN round-trips complete.
    'iceCandidatePoolSize': 2,
  };

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  /// Whether setRemoteDescription has completed — guards ICE candidate queueing.
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  /// Fires each time a new ICE candidate is gathered locally.
  final _iceCandidateController =
      StreamController<RTCIceCandidate>.broadcast();
  Stream<RTCIceCandidate> get onIceCandidate =>
      _iceCandidateController.stream;

  /// Fires when the remote peer disconnects.
  final _disconnectedController = StreamController<void>.broadcast();
  Stream<void> get onDisconnected => _disconnectedController.stream;

  // ── Setup ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    LogService.log('Initializing WebRTC PeerConnection');
    _pc = await createPeerConnection(_iceServers);

    _pc!.onIceCandidate = (candidate) {
      final sdp = candidate.candidate ?? '';
      final type = sdp.contains('typ relay')
          ? 'relay'
          : sdp.contains('typ srflx')
              ? 'srflx'
              : 'host';
      LogService.log('ICE candidate gathered [$type]');
      if (!_iceCandidateController.isClosed) {
        _iceCandidateController.add(candidate);
      }
    };

    _pc!.onIceConnectionState = (state) {
      LogService.log('ICE Connection State: $state');
    };

    _pc!.onConnectionState = (state) {
      LogService.log('WebRTC Connection State: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (!_disconnectedController.isClosed) {
          _disconnectedController.add(null);
        }
      }
    };

    // Handle incoming remote tracks — required for audio to be activated
    _pc!.onTrack = (RTCTrackEvent event) {
      LogService.log('Remote track received: ${event.track.kind}');
    };

    // Default to earpiece (standard phone-call behaviour)
    await Helper.setSpeakerphoneOn(false);

    // Capture microphone audio
    LogService.log('Requesting microphone access');
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    for (final track in _localStream!.getAudioTracks()) {
      _pc!.addTrack(track, _localStream!);
    }
  }

  // ── Offer / Answer ────────────────────────────────────────────────────────

  Future<RTCSessionDescription> createOffer() async {
    LogService.log('Creating WebRTC Offer');
    final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    LogService.log('Creating WebRTC Answer');
    final answer = await _pc!.createAnswer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription sdp) async {
    LogService.log('Setting WebRTC Remote Description');
    await _pc!.setRemoteDescription(sdp);
    _remoteDescriptionSet = true;
    // Flush any candidates that arrived before remote description was ready
    if (_pendingCandidates.isNotEmpty) {
      LogService.log('Flushing ${_pendingCandidates.length} queued ICE candidates');
      for (final c in _pendingCandidates) {
        await _pc!.addCandidate(c);
      }
      _pendingCandidates.clear();
    }
  }

  /// Adds a remote ICE candidate — queued if remote description not yet set.
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    if (!_remoteDescriptionSet) {
      LogService.log('Queuing remote ICE candidate (remote desc not set yet)');
      _pendingCandidates.add(candidate);
      return;
    }
    LogService.log('Adding Remote ICE candidate');
    await _pc!.addCandidate(candidate);
  }

  // ── Audio routing ─────────────────────────────────────────────────────────

  Future<void> setSpeakerOn(bool on) async {
    LogService.log('Speaker ${on ? 'ON' : 'OFF (earpiece)'}');
    await Helper.setSpeakerphoneOn(on);
  }

  // ── Mute ──────────────────────────────────────────────────────────────────

  void setMuted(bool muted) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  // ── Teardown ──────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    if (_pc == null) return; // Guard against double-dispose
    LogService.log('Disposing WebRTC Service');
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
    await _pc?.close();
    _pc = null;
    _pendingCandidates.clear();
    if (!_iceCandidateController.isClosed) {
      await _iceCandidateController.close();
    }
    if (!_disconnectedController.isClosed) {
      await _disconnectedController.close();
    }
  }
}
