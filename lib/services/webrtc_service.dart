import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Wraps a single WebRTC peer connection for a voice call.
/// Video tracks are not created here — audio only.
class WebRtcService {
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

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
    _pc = await createPeerConnection(_iceServers);

    _pc!.onIceCandidate = (candidate) {
      if (!_iceCandidateController.isClosed) {
        _iceCandidateController.add(candidate);
      }
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (!_disconnectedController.isClosed) {
          _disconnectedController.add(null);
        }
      }
    };

    // Capture microphone audio
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
    final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    final answer = await _pc!.createAnswer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription sdp) async {
    await _pc!.setRemoteDescription(sdp);
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _pc!.addCandidate(candidate);
  }

  // ── Mute ──────────────────────────────────────────────────────────────────

  void setMuted(bool muted) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  // ── Teardown ──────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
    await _pc?.close();
    _pc = null;
    await _iceCandidateController.close();
    await _disconnectedController.close();
  }
}
