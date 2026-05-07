  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            SizedBox(
              width: 0,
              height: 0,
              child: RTCVideoView(_remoteRenderer),
            ),
            Column(
              children: [
                const SizedBox(height: 60),
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
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
        ),
      ),
    );
  }
