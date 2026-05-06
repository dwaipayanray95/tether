# Release Notes - v1.1.7

## New Features
### 📞 Voice Calling (WebRTC)
A robust, real-time voice calling system is now integrated into Tether.
- **Native Call UI**: Incoming calls now trigger the native system ringer (CallKit on iOS, ConnectionService on Android), allowing you to answer even when the phone is locked.
- **Low-Latency Audio**: Powered by WebRTC with Opus compression for crystal clear, real-time voice with minimal data usage.
- **Reliable Connectivity**: Integrated with a custom signaling server on Oracle Cloud and Metered STUN/TURN servers to ensure calls connect across any network (Wi-Fi or Mobile Data).
- **In-App Call Screen**: A clean, dedicated screen for active calls with Mute, Speakerphone, and Call Duration tracking.

## Infrastructure Improvements
- **Signaling Server**: Deployed a dedicated Node.js signaling server on Oracle Cloud Always-Free tier.
- **STUN/TURN**: Configured global relay servers via Metered.ca for high-reliability peer-to-peer connections.

## Technical Changes
- Added `flutter_webrtc`, `flutter_callkit_incoming`, and `socket_io_client` dependencies.
- Updated Android permissions and `minSdkVersion` (set to 24).
- Configured iOS background modes for VOIP and Audio.
- New services: `WebRTCService`, `SignalingService`, and `CallHandlerService`.
