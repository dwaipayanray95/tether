import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'signaling_service.dart';
import 'webrtc_service.dart';
import 'auth_service.dart';
import 'log_service.dart';
import 'nav_service.dart';
import '../screens/call_screen.dart';
import 'package:flutter/material.dart';

class CallHandlerService {
  static final CallHandlerService _instance = CallHandlerService._internal();
  factory CallHandlerService() => _instance;
  CallHandlerService._internal();

  late SignalingService _signalingService;
  late WebRTCService _webrtcService;
  final AuthService _authService = AuthService();
  
  String? _currentCallId;
  String? _remoteUserId;

  void initialize() {
    final user = _authService.currentUser;
    if (user == null) return;

    _signalingService = SignalingService(userId: user.uid);
    _webrtcService = WebRTCService();

    _signalingService.onOffer = _handleIncomingOffer;
    _signalingService.onAnswer = _handleAnswer;
    _signalingService.onIceCandidate = _handleIceCandidate;

    _signalingService.connect();

    // Listen to CallKit events
    FlutterCallkitIncoming.onEvent.listen((event) {
      switch (event!.event) {
        case Event.actionCallIncoming:
          LogService.log('CallKit: Incoming Call');
          break;
        case Event.actionCallAccept:
          LogService.log('CallKit: Call Accepted');
          _acceptCall();
          break;
        case Event.actionCallDecline:
          LogService.log('CallKit: Call Declined');
          _declineCall();
          break;
        case Event.actionCallEnded:
          LogService.log('CallKit: Call Ended');
          _endCall();
          break;
        default:
          break;
      }
    });
  }

  // ── Outgoing Call ─────────────────────────────────────────────────────────

  Future<void> makeCall(String targetUserId, String targetUserName) async {
    _remoteUserId = targetUserId;
    _currentCallId = const Uuid().v4();

    await _webrtcService.initLocalStream();
    await _webrtcService.setupPeerConnection();

    _webrtcService.peerConnection!.onIceCandidate = (candidate) {
      _signalingService.sendIceCandidate(_remoteUserId!, candidate.toMap());
    };

    final offer = await _webrtcService.createOffer();
    _signalingService.sendOffer(_remoteUserId!, offer.toMap());

    // Navigate to Call Screen
    _navigateToCallScreen(targetUserName, isOutgoing: true);
  }

  // ── Incoming Call ─────────────────────────────────────────────────────────

  void _handleIncomingOffer(Map<String, dynamic> data) async {
    _remoteUserId = data['from'];
    _currentCallId = const Uuid().v4(); // In a real app, use a shared ID from signaling

    // Show CallKit UI
    final callConfig = CallKitParams(
      id: _currentCallId!,
      nameCaller: _authService.partnerName,
      appName: 'Tether',
      type: 0, // 0 for audio
      duration: 30000,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#090909',
        backgroundUrl: 'https://i.pravatar.cc/100', // Placeholder
        actionColor: '#4CAF50',
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callConfig);
    
    // Store offer for when user accepts
    _pendingOffer = data['sdp'];
  }

  Map<String, dynamic>? _pendingOffer;

  Future<void> _acceptCall() async {
    if (_pendingOffer == null) return;

    await _webrtcService.initLocalStream();
    await _webrtcService.setupPeerConnection();

    _webrtcService.peerConnection!.onIceCandidate = (candidate) {
      _signalingService.sendIceCandidate(_remoteUserId!, candidate.toMap());
    };

    await _webrtcService.setRemoteDescription(
      RTCSessionDescription(_pendingOffer!['sdp'], _pendingOffer!['type']),
    );

    final answer = await _webrtcService.createAnswer();
    _signalingService.sendAnswer(_remoteUserId!, answer.toMap());

    _pendingOffer = null;
    
    _navigateToCallScreen(_authService.partnerName, isOutgoing: false);
  }

  void _handleAnswer(Map<String, dynamic> data) async {
    await _webrtcService.setRemoteDescription(
      RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type']),
    );
  }

  void _handleIceCandidate(Map<String, dynamic> data) async {
    await _webrtcService.addIceCandidate(
      RTCIceCandidate(data['candidate']['candidate'], data['candidate']['sdpMid'], data['candidate']['sdpMLineIndex']),
    );
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  void _declineCall() {
    _pendingOffer = null;
    // Send rejection signaling if needed
  }

  void _endCall() {
    _webrtcService.dispose();
    FlutterCallkitIncoming.endAllCalls();
    if (navigatorKey.currentState?.canPop() ?? false) {
      navigatorKey.currentState?.pop();
    }
  }

  void _navigateToCallScreen(String userName, {required bool isOutgoing}) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          userName: userName,
          isOutgoing: isOutgoing,
          webrtcService: _webrtcService,
          onHangup: _endCall,
        ),
      ),
    );
  }
}
