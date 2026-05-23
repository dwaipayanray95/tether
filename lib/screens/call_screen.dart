import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';
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

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  Timer? _timer;
  int _seconds = 0;
  RTCIceConnectionState _connectionState = RTCIceConnectionState.RTCIceConnectionStateNew;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  late AnimationController _rippleController;

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _startTimer();
    
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

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
    _rippleController.dispose();
    super.dispose();
  }

  Widget _buildRipple(double scale, double opacity) {
    return Container(
      width: 130 * scale,
      height: 130 * scale,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE8715A).withValues(alpha: opacity * 0.15),
        border: Border.all(
          color: const Color(0xFFE8715A).withValues(alpha: opacity * 0.25),
          width: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionState == RTCIceConnectionState.RTCIceConnectionStateConnected;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Premium Ambient Background ─────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0B0909),
                  Color(0xFF140F0E),
                  Color(0xFF1A1110),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          
          // Organic Glow Spotlight Top-Left
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE8715A),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // Organic Glow Spotlight Bottom-Right
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 350,
              height: 350,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFB5838D),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // Hidden WebRTC Video Renderer
          SizedBox(
            width: 0,
            height: 0,
            child: RTCVideoView(_remoteRenderer),
          ),

          // ── UI Content Scaffold ────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 80),
                
                // Pulsing Avatar Stack
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Rippling animations when connected
                    if (isConnected)
                      AnimatedBuilder(
                        animation: _rippleController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              _buildRipple(1.0 + _rippleController.value * 0.8, 1.0 - _rippleController.value),
                              _buildRipple(1.0 + ((_rippleController.value + 0.5) % 1.0) * 0.8, 1.0 - ((_rippleController.value + 0.5) % 1.0)),
                            ],
                          );
                        },
                      )
                    else
                      // Static glowing ring when calling
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFE8715A).withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                      ),

                    // Avatar Circle
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE8715A).withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: const Color(0xFF2E2220),
                        child: Text(
                          widget.userName[0].toUpperCase(),
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 48,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFFFF0EE),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                // Partner Name
                Text(
                  widget.userName,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Call Status Indicator
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    isConnected ? _formatDuration(_seconds) : _getStatusText(),
                    key: ValueKey<String>(isConnected ? 'dur' : _getStatusText()),
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isConnected ? const Color(0xFFE8715A) : Colors.white70,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                
                const Spacer(),
                
                // ── Glassmorphic Call Actions Footer ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 60, left: 32, right: 32),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Mute Microphone Button
                            _IconButton(
                              icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                              color: _isMuted ? const Color(0xFFE8715A) : Colors.white.withValues(alpha: 0.08),
                              iconColor: Colors.white,
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  _isMuted = !_isMuted;
                                  widget.webrtcService.toggleMute(_isMuted);
                                });
                              },
                            ),
                            
                            // End Call Button (Large, Vibrant Red)
                            _IconButton(
                              icon: Icons.call_end_rounded,
                              color: Colors.redAccent.shade400,
                              iconColor: Colors.white,
                              size: 72,
                              onPressed: () {
                                HapticFeedback.heavyImpact();
                                widget.onHangup();
                              },
                            ),
                            
                            // Speakerphone Toggle
                            _IconButton(
                              icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                              color: _isSpeakerOn ? const Color(0xFFE8715A) : Colors.white.withValues(alpha: 0.08),
                              iconColor: Colors.white,
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  _isSpeakerOn = !_isSpeakerOn;
                                  widget.webrtcService.toggleSpeakerphone(_isSpeakerOn);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    this.size = 56,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(size / 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            if (icon == Icons.call_end_rounded)
              BoxShadow(
                color: Colors.redAccent.withValues(alpha: 0.3),
                blurRadius: 15,
                spreadRadius: 1,
              )
          ],
        ),
        child: Icon(icon, color: iconColor, size: size * 0.45),
      ),
    );
  }
}
