import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/webrtc_service.dart';
import '../services/log_service.dart';
import '../theme/app_theme.dart';

enum _CallState {
  connecting,    // outgoing: setting up WebRTC
  ringing,       // outgoing: waiting for partner to answer
  incomingRing,  // incoming: showing accept/decline to THIS user
  active,
  ended,
}

/// Full-screen voice call UI.
///
/// [isOutgoing] = true  → we placed the call.
/// [isOutgoing] = false → partner called us; show ringing UI first.
/// [callId] is required for incoming calls; may be null for outgoing.
class CallScreen extends StatefulWidget {
  final bool isOutgoing;
  final String partnerName;
  final String? callId;

  const CallScreen({
    super.key,
    required this.isOutgoing,
    required this.partnerName,
    this.callId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _auth = AuthService();
  final _webrtc = WebRtcService();
  final _ringtone = FlutterRingtonePlayer();

  _CallState _state = _CallState.connecting;
  bool _muted = false;
  bool _speakerOn = false;
  String? _callId;
  Timer? _durationTimer;
  int _seconds = 0;
  bool _ringtoneActive = false;

  StreamSubscription? _disconnectedSub;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _disconnectedSub?.cancel();
    _stopRingtone();
    _webrtc.dispose();
    super.dispose();
  }

  // ── Ringtone ──────────────────────────────────────────────────────────────

  void _startRingtone() {
    if (_ringtoneActive) return;
    _ringtoneActive = true;
    LogService.log('Starting ringtone');
    _ringtone.play(
      android: AndroidSounds.ringtone,
      ios: IosSounds.electronic,
      looping: true,
      volume: 1.0,
      asAlarm: false,
    );
  }

  void _stopRingtone() {
    if (!_ringtoneActive) return;
    _ringtoneActive = false;
    LogService.log('Stopping ringtone');
    _ringtone.stop();
  }

  // ── Start ─────────────────────────────────────────────────────────────────

  Future<void> _start() async {
    await _webrtc.init();

    _disconnectedSub = _webrtc.onDisconnected.listen((_) {
      if (mounted && _state != _CallState.ended) _hangUp(remote: true);
    });

    if (widget.isOutgoing) {
      await _startOutgoing();
    } else {
      // Show ringing UI — wait for user to tap Accept/Decline
      setState(() => _state = _CallState.incomingRing);
      _startRingtone();
    }
  }

  // ── Outgoing ──────────────────────────────────────────────────────────────

  Future<void> _startOutgoing() async {
    setState(() => _state = _CallState.ringing);
    final offer = await _webrtc.createOffer();

    _callId = await CallService.startCall(
      callerName: _auth.myName,
      offer: offer,
      onAnswer: (answer) async {
        await _webrtc.setRemoteDescription(answer);
        if (mounted) {
          setState(() => _state = _CallState.active);
          _startTimer();
        }
      },
      onRemoteCandidate: (c) => _webrtc.addIceCandidate(c),
    );

    // Forward our ICE candidates to Firestore
    _webrtc.onIceCandidate.listen((c) {
      if (_callId != null) CallService.sendCallerCandidate(_callId!, c);
    });
  }

  // ── Incoming: Accept ──────────────────────────────────────────────────────

  Future<void> _acceptCall() async {
    _stopRingtone();
    HapticFeedback.mediumImpact();
    setState(() => _state = _CallState.connecting);
    await _answerIncoming();
  }

  Future<void> _answerIncoming() async {
    _callId = widget.callId!;

    // 1. Fetch the offer from Firestore
    final doc = await CallService.getCall(_callId!);
    final data = doc.data();
    if (data == null || data['offer'] == null) {
      _hangUp();
      return;
    }

    final offerMap = Map<String, dynamic>.from(data['offer']);
    final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);

    // 2. Set remote description (the offer)
    await _webrtc.setRemoteDescription(offer);

    // 3. Forward callee candidates as they gather
    _webrtc.onIceCandidate.listen((c) {
      CallService.sendCalleeCandidate(_callId!, c);
    });

    // 4. Create and send the answer
    final answer = await _webrtc.createAnswer();
    await CallService.answerCall(
      callId: _callId!,
      answer: answer,
      onRemoteCandidate: (c) => _webrtc.addIceCandidate(c),
    );

    if (mounted) {
      setState(() => _state = _CallState.active);
      _startTimer();
    }
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  String get _durationLabel {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _webrtc.setMuted(_muted);
    HapticFeedback.lightImpact();
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    HapticFeedback.lightImpact();
  }

  Future<void> _hangUp({bool remote = false}) async {
    if (_state == _CallState.ended) return;
    setState(() => _state = _CallState.ended);
    _durationTimer?.cancel();
    _disconnectedSub?.cancel(); // Cancel before dispose to prevent re-trigger
    _stopRingtone();
    final idToEnd = _callId ?? widget.callId;
    if (idToEnd != null && !remote) {
      await CallService.endCall(idToEnd);
    }
    await _webrtc.dispose();
    if (mounted) Navigator.of(context).pop();
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Avatar
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.25),
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.5), width: 3),
              ),
              child: Center(
                child: Text(
                  widget.partnerName[0].toUpperCase(),
                  style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.partnerName,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              _statusLabel,
              style: TextStyle(
                  fontSize: 15, color: Colors.white.withValues(alpha: 0.6)),
            ),
            const Spacer(),
            // Controls
            _state == _CallState.incomingRing
                ? _buildIncomingControls()
                : _buildActiveControls(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// Accept / Decline buttons shown while the incoming call is ringing.
  Widget _buildIncomingControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Decline
          _ControlButton(
            icon: Icons.call_end_rounded,
            label: 'Decline',
            onTap: () => _hangUp(),
            isHangup: true,
          ),
          // Accept
          _ControlButton(
            icon: Icons.call_rounded,
            label: 'Accept',
            onTap: _acceptCall,
            isAccept: true,
          ),
        ],
      ),
    );
  }

  /// Mute / End / Speaker controls shown during an active call.
  Widget _buildActiveControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: _muted ? Icons.mic_off : Icons.mic,
            label: _muted ? 'Unmute' : 'Mute',
            onTap: _state == _CallState.active ? _toggleMute : null,
            active: _muted,
          ),
          _ControlButton(
            icon: Icons.call_end_rounded,
            label: 'End',
            onTap: () => _hangUp(),
            isHangup: true,
          ),
          _ControlButton(
            icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
            label: _speakerOn ? 'Speaker' : 'Earpiece',
            onTap: _state == _CallState.active ? _toggleSpeaker : null,
            active: _speakerOn,
          ),
        ],
      ),
    );
  }

  String get _statusLabel {
    switch (_state) {
      case _CallState.connecting:
        return 'Connecting…';
      case _CallState.ringing:
        return 'Ringing…';
      case _CallState.incomingRing:
        return 'Incoming call';
      case _CallState.active:
        return _durationLabel;
      case _CallState.ended:
        return 'Call ended';
    }
  }
}

// ── Control button ────────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool isHangup;
  final bool isAccept;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.isHangup = false,
    this.isAccept = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isHangup
        ? Colors.red
        : isAccept
            ? Colors.green
            : active
                ? AppTheme.primary
                : Colors.white.withValues(alpha: 0.15);
    final iconColor =
        (isHangup || isAccept || active) ? Colors.white : Colors.white.withValues(alpha: 0.8);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: onTap == null
                  ? Colors.white.withValues(alpha: 0.08)
                  : bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}
