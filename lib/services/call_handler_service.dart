import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'signaling_service.dart';
import 'webrtc_service.dart';
import 'auth_service.dart';
import 'fcm_service.dart';
import 'log_service.dart';
import 'nav_service.dart';
import '../screens/call_screen.dart';
import 'package:flutter/material.dart';

class CallHandlerService {
  static final CallHandlerService _instance = CallHandlerService._internal();
  factory CallHandlerService() => _instance;
  CallHandlerService._internal();

  SignalingService? _signalingService;
  SignalingService? get signalingService => _signalingService;
  late WebRTCService _webrtcService;
  final AuthService _authService = AuthService();
  bool _isInitialized = false;
  
  String? _currentCallId;
  String? _remoteUserId;

  // ICE Candidate Queue
  final List<Map<String, dynamic>> _pendingIceCandidates = [];
  bool _remoteDescriptionSet = false;

  void initialize() {
    if (_isInitialized) return;
    final user = _authService.currentUser;
    if (user == null) return;

    _signalingService = SignalingService(userId: user.uid);
    _webrtcService = WebRTCService();

    _signalingService!.onOffer = _handleIncomingOffer;
    _signalingService!.onAnswer = _handleAnswer;
    _signalingService!.onIceCandidate = _handleIceCandidate;
    
    _signalingService!.onUserJoined = (joinedUserId) {
      if (joinedUserId == _remoteUserId && _isMakingOutgoingCall) {
        _isMakingOutgoingCall = false;
        _sendWebRTCOffer();
      }
    };

    _signalingService!.onCallPing = (callerName) {
      showIncomingCall(callerName);
    };

    _signalingService!.onCallEnded = (from) {
      LogService.log('Remote call ended signaled. Terminating call locally.');
      endCall(remote: true);
    };

    _signalingService!.connect();
    _isInitialized = true;

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
          endCall();
          break;
        default:
          break;
      }
    });
  }

  // ── Outgoing Call ─────────────────────────────────────────────────────────

  bool _isMakingOutgoingCall = false;

  Future<void> makeCall(String targetUserId, String targetUserName) async {
    _remoteUserId = targetUserId;
    _currentCallId = const Uuid().v4();
    _isMakingOutgoingCall = true;

    // Reset ICE state
    _pendingIceCandidates.clear();
    _remoteDescriptionSet = false;

    // 1. Send Direct FCM Call Ping (Wakes the partner instantly even if background/offline)
    await FcmService.send(
      partnerName: targetUserName,
      title: '📞 Incoming Call',
      body: '${_authService.myName} is calling you...',
      type: 'call_ping',
      extra: {
        'callerName': _authService.myName,
      },
    );

    // 2. Make sure signaling is initialized & connected
    initialize();
    _signalingService?.connect();

    // 3. Send Signaling Ping as backup
    _signalingService?.sendCallPing(targetUserId, _authService.myName);

    // 4. Prepare WebRTC locally
    await _webrtcService.initLocalStream();

    LogService.log('Call Ping sent. Waiting for partner to join signaling...');

    // Navigate to Call Screen immediately to show "Calling..."
    _navigateToCallScreen(targetUserName, isOutgoing: true);
  }

  Future<void> _sendWebRTCOffer() async {
    LogService.log('Partner joined. Sending WebRTC Offer...');
    await _webrtcService.setupPeerConnection();

    _webrtcService.peerConnection!.onIceCandidate = (candidate) {
      if (_remoteUserId != null) {
        _signalingService?.sendIceCandidate(_remoteUserId!, candidate.toMap());
      }
    };

    final offer = await _webrtcService.createOffer();
    _signalingService?.sendOffer(_remoteUserId!, offer.toMap());
  }

  // ── Incoming Call ─────────────────────────────────────────────────────────

  Future<void> showIncomingCall(String callerName) async {
    _currentCallId = const Uuid().v4();
    
    final callConfig = CallKitParams(
      id: _currentCallId!,
      nameCaller: callerName,
      appName: 'Tether',
      type: 0,
      duration: 30000,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'ringtone_default',
        backgroundColor: '#090909',
        actionColor: '#4CAF50',
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callConfig);
  }

  void _handleIncomingOffer(Map<String, dynamic> data) async {
    LogService.log('Received WebRTC Offer via signaling');
    _remoteUserId = data['from'];
    _pendingOffer = data['sdp'];
  }

  Map<String, dynamic>? _pendingOffer;

  Future<void> _acceptCall() async {
    // Ensure signaling is connected if we were woken up from background
    initialize();
    _signalingService?.connect();

    // Reset ICE state
    _pendingIceCandidates.clear();
    _remoteDescriptionSet = false;

    if (_pendingOffer == null) {
      // If we haven't received the offer yet, wait up to 10 seconds
      LogService.log('Call accepted but no offer received yet. Waiting...');
      int retries = 0;
      while (_pendingOffer == null && retries < 20) {
        await Future.delayed(const Duration(milliseconds: 500));
        retries++;
      }
    }

    if (_pendingOffer == null) {
      LogService.log('FAILED: No offer received after 10s wait.');
      endCall();
      return;
    }

    await _webrtcService.initLocalStream();
    await _webrtcService.setupPeerConnection();

    _webrtcService.peerConnection!.onIceCandidate = (candidate) {
      if (_remoteUserId != null) {
        _signalingService?.sendIceCandidate(_remoteUserId!, candidate.toMap());
      }
    };

    await _webrtcService.setRemoteDescription(
      RTCSessionDescription(_pendingOffer!['sdp'], _pendingOffer!['type']),
    );
    await _drainIceCandidates();

    final answer = await _webrtcService.createAnswer();
    _signalingService?.sendAnswer(_remoteUserId!, answer.toMap());

    _pendingOffer = null;
    
    _navigateToCallScreen(_authService.partnerName, isOutgoing: false);
  }

  void _handleAnswer(Map<String, dynamic> data) async {
    await _webrtcService.setRemoteDescription(
      RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type']),
    );
    await _drainIceCandidates();
  }

  void _handleIceCandidate(Map<String, dynamic> data) async {
    if (_remoteDescriptionSet) {
      await _webrtcService.addIceCandidate(
        RTCIceCandidate(data['candidate']['candidate'], data['candidate']['sdpMid'], data['candidate']['sdpMLineIndex']),
      );
    } else {
      LogService.log('Queueing early ICE candidate.');
      _pendingIceCandidates.add(data);
    }
  }

  Future<void> _drainIceCandidates() async {
    _remoteDescriptionSet = true;
    if (_pendingIceCandidates.isNotEmpty) {
      LogService.log('Draining ${_pendingIceCandidates.length} queued ICE candidates');
      for (final data in _pendingIceCandidates) {
        try {
          await _webrtcService.addIceCandidate(
            RTCIceCandidate(data['candidate']['candidate'], data['candidate']['sdpMid'], data['candidate']['sdpMLineIndex']),
          );
        } catch (e) {
          LogService.log('Failed to add queued ICE candidate: $e');
        }
      }
      _pendingIceCandidates.clear();
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  void _declineCall() {
    _pendingOffer = null;
    endCall();
  }

  void endCall({bool remote = false}) {
    LogService.log('Hanging up call (remote: $remote)');
    
    if (!remote && _remoteUserId != null) {
      // 1. Send direct FCM call_ended to terminate ringing immediately on partner's device
      FcmService.send(
        partnerName: _authService.partnerName,
        title: 'Call Ended',
        body: 'Call ended',
        type: 'call_ended',
      );
      // 2. Emit call-ended via signaling
      _signalingService?.sendCallEnded(_remoteUserId!);
    }

    _webrtcService.dispose();
    FlutterCallkitIncoming.endAllCalls();

    _currentCallId = null;
    _remoteUserId = null;
    _pendingOffer = null;
    _isMakingOutgoingCall = false;
    _pendingIceCandidates.clear();
    _remoteDescriptionSet = false;

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
          onHangup: endCall,
        ),
      ),
    );
  }
}
