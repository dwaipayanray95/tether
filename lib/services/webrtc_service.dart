import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../config/webrtc_config.dart';
import 'log_service.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  Function(MediaStream)? onRemoteStream;
  Function(RTCIceConnectionState)? onIceConnectionStateChange;

  Future<void> initLocalStream() async {
    _localStream = await navigator.mediaDevices.getUserMedia(WebRTCConfig.mediaConstraints);
  }

  Future<void> createPeerConnection() async {
    _peerConnection = await createPeerConnection(
      {
        'iceServers': WebRTCConfig.iceServers,
        'sdpSemantics': 'unified-plan',
      },
      WebRTCConfig.dcConstraints,
    );

    _peerConnection!.onIceConnectionState = (state) {
      LogService.log('ICE Connection State: $state');
      onIceConnectionStateChange?.call(state);
    };

    _peerConnection!.onIceCandidate = (candidate) {
      // This will be handled by the caller and sent via signaling
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };

    // Add local stream tracks to peer connection
    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });
  }

  Future<RTCSessionDescription> createOffer() async {
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    await _peerConnection!.setRemoteDescription(description);
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _peerConnection!.addIceCandidate(candidate);
  }

  void toggleMute(bool isMuted) {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !isMuted;
    });
  }

  void toggleSpeakerphone(bool isSpeakerOn) {
    Helper.setSpeakerphoneOn(isSpeakerOn);
  }

  Future<void> dispose() async {
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    await _peerConnection?.close();
    await _peerConnection?.dispose();
  }

  RTCPeerConnection? get peerConnection => _peerConnection;
}
