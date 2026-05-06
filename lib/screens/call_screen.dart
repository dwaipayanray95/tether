import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/audio_relay_service.dart';
import '../services/fcm_service.dart';
import '../services/proximity_service.dart';
import '../services/log_service.dart';
import '../theme/app_theme.dart';

enum _CallState {
  connecting,    // initial state
  ringing,       // outgoing: waiting for partner to answer
  incomingRing,  // incoming: showing accept/decline to THIS user
  active,
  ended,
}

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
  final _relay = AudioRelayService();
  final _ringtone = FlutterRingtonePlayer();

  _CallState _state = _CallState.connecting;
  bool _muted = false;
  bool _speakerOn = false;
  String? _callId;
  Timer? _durationTimer;
  int _seconds = 0;
  bool _ringtoneActive = false;

  StreamSubscription? _callStatusSub;

  @override
  void initState() {
    super.initState();
    ProximityService.acquire();
    _start();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _callStatusSub?.cancel();
    _stopRingtone();
    ProximityService.release();
    _relay.stop();
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
    if (widget.isOutgoing) {
      setState(() => _state = _CallState.ringing);
      _callId = await CallService.startCall(callerName: _auth.myName);
      _watchCallStatus(_callId!);
    } else {
      _callId = widget.callId;
      if (_callId != null) {
        _watchCallStatus(_callId!);
      }
      setState(() => _state = _CallState.incomingRing);
      _startRingtone();
    }
  }

  void _watchCallStatus(String callId) {
    _callStatusSub = CallService.callStatusStream(callId).listen((status) async {
      LogService.log('Call status update: $status');
      if (status == 'active' && _state != _CallState.active) {
        _stopRingtone();
        setState(() => _state = _CallState.active);
        _startTimer();
        await _relay.start(
          callId,
          _auth.myName.toLowerCase(),
          widget.partnerName.toLowerCase(),
        );
      } else if ((status == 'ended' || status == null) &&
          mounted &&
          _state != _CallState.ended) {
        LogService.log('Call $callId ended remotely');
        _hangUp(remote: true);
      }
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _acceptCall() async {
    _stopRingtone();
    HapticFeedback.mediumImpact();
    if (_callId != null) {
      await CallService.acceptCall(_callId!);
    }
  }

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

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _relay.setMuted(_muted);
    HapticFeedback.lightImpact();
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    _relay.setSpeakerOn(_speakerOn);
    HapticFeedback.lightImpact();
  }

  Future<void> _hangUp({bool remote = false}) async {
    if (_state == _CallState.ended) return;
    setState(() => _state = _CallState.ended);
    _durationTimer?.cancel();
    _callStatusSub?.cancel();
    _stopRingtone();
    
    final idToEnd = _callId ?? widget.callId;
    if (idToEnd != null && !remote) {
      await CallService.endCall(idToEnd);
      // Tell partner's device to dismiss its incoming call notification
      FcmService.send(
        partnerName: widget.partnerName.toLowerCase(),
        title: '',
        body: '',
        type: 'call_ended',
        extra: {'callId': idToEnd},
      );
    }
    
    await _relay.stop();
    
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
            _state == _CallState.incomingRing
                ? _buildIncomingControls()
                : _buildActiveControls(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: Icons.call_end_rounded,
            label: 'Decline',
            onTap: () => _hangUp(),
            isHangup: true,
          ),
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
