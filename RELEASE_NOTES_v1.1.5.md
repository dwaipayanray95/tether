# Release Notes - v1.1.5

## 🚀 New Feature: Reliable D2D Calls
We've completely overhauled the calling system to ensure it works reliably even on cellular networks (carrier NATs).

- **Firebase RTDB Audio Relay**: Replaced WebRTC with a custom Firebase-backed audio transport.
- **Opus Compression**: High-quality audio with extremely low data usage (~15MB/hr), ensuring you stay well within the free tier limits.
- **Instant Connection**: Calls now transition to 'Active' status immediately upon acceptance, without waiting for ICE candidate gathering.
- **Simplified Signaling**: Removed complex WebRTC machinery for a leaner, more robust codebase.

## 🛠 Improvements
- Optimized `CallService` and `CallScreen` for better performance.
- Improved cleanup of temporary call data in Realtime Database.
- Removed obsolete `flutter_webrtc` dependency.
