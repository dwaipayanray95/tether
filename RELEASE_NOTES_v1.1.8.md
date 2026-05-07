# Release Notes - v1.1.8

## Critical Fixes
### 📞 Improved Voice Calling
- **Full-Screen Background Calls**: Fixed Android CallKit parameters to ensure the call screen triggers a full-screen, high-priority intent, even when the phone is locked.
- **Audio Routing Fix**: Implemented `RTCVideoRenderer` to correctly route incoming WebRTC audio tracks to the device earpiece/speaker.
- **Connection Reliability**: Resolved "Connection refused" signaling errors by patching the Node.js server to handle offline state and connection routing correctly.

### 🔔 Notifications Migration
- **Self-Hosted Notification Engine**: Migrated all push notifications (calls, messages, pokes) from Firebase Functions to our private Oracle Cloud Signaling Server. This removes the need for the Firebase Blaze plan and ensures real-time reliability.
- **Background Wakeup**: Added FCM "call-ping" functionality to wake backgrounded apps for incoming calls.

## Technical Improvements
- **Hybrid Signaling**: Refactored the call flow to prioritize WebSocket connectivity while using FCM as a "wake-up" layer for background devices.
- **Dependency Cleanup**: Removed invalid Android CallKit parameters that were causing build failures.
