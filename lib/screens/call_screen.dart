import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_service.dart';

class CallScreen extends StatefulWidget {
  final String userName;
  final bool isOutgoing;
  final WebRTCService webrtcService;
  final VoidCallback onHangup;

  const CallScreen({
    super.key,
    required this.userName,
    required this.isOutgoing,
    required this.webrtcService,
    required this.onHangup,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  Timer? _timer;
  int _seconds = 0;
  RTCIceConnectionState _connectionState = RTCIceConnectionState.RTCIceConnectionStateNew;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _startTimer();
    widget.webrtcService.onIceConnectionStateChange = (state) {
      if (mounted) {
        setState(() {
          _connectionState = state;
        });
      }
    };
  }

  Future<void> _initRenderer() async {
    await _remoteRenderer.initialize();
    widget.webrtcService.onRemoteStream = (stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      }
    };
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _seconds++;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Hidden video view is REQUIRED by flutter_webrtc to play audio streams
            SizedBox(
              width: 0,
              height: 0,
              child: RTCVideoView(_remoteRenderer),
            ),
            Column(
              children: [
                const SizedBox(height: 60),
            // User Info
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[800],
              child: Text(
                widget.userName[0].toUpperCase(),
                style: const TextStyle(fontSize: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.userName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              _connectionState == RTCIceConnectionState.RTCIceConnectionStateConnected
                  ? _formatDuration(_seconds)
                  : _getStatusText(),
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const Spacer(),
            // Controls
            Padding(
              padding: const Duration(milliseconds: 300) > Duration.zero 
                  ? const EdgeInsets.only(bottom: 60)
                  : EdgeInsets.zero,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _IconButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    color: _isMuted ? Colors.white : Colors.white24,
                    iconColor: _isMuted ? Colors.black : Colors.white,
                    onPressed: () {
                      setState(() {
                        _isMuted = !_isMuted;
                        widget.webrtcService.toggleMute(_isMuted);
                      });
                    },
                  ),
                  _IconButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    iconColor: Colors.white,
                    size: 70,
                    onPressed: widget.onHangup,
                  ),
                  _IconButton(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    color: _isSpeakerOn ? Colors.white : Colors.white24,
                    iconColor: _isSpeakerOn ? Colors.black : Colors.white,
                    onPressed: () {
                      setState(() {
                        _isSpeakerOn = !_isSpeakerOn;
                        widget.webrtcService.toggleSpeakerphone(_isSpeakerOn);
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getStatusText() {
    switch (_connectionState) {
      case RTCIceConnectionState.RTCIceConnectionStateNew:
      case RTCIceConnectionState.RTCIceConnectionStateChecking:
        return widget.isOutgoing ? 'Calling...' : 'Connecting...';
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
        return 'Connected';
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        return 'Connection Failed';
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        return 'Disconnected';
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        return 'Call Ended';
      default:
        return '';
    }
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final double size;
  final VoidCallback onPressed;

  const _IconButton({
    required this.icon,
    required this.color,
    required this.iconColor,
    this.size = 60,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: size * 0.5),
      ),
    );
  }
}
