# Removed Features & Notification Discrepancies

This document logs features that were previously designed or partially documented but have been removed from the current active codebase. It also highlights critical discrepancies in the notification system between historical assumptions and the actual implementation.

---

## 🚫 Removed Features

### 1. Voice Calling Feature
- **Removed Screens:** `lib/screens/call_screen.dart` (the entire full-screen calling UI).
- **Removed Services:**
  - `lib/services/call_service.dart` (Firestore signalling logic).
  - `lib/services/audio_relay_service.dart` (Bi-directional RTDB Opus encoding/decoding streaming).
- **Details:** The app no longer supports voice calling. Any incoming call streams or signaling pipelines have been fully removed.

### 2. Proximity Sensor & Native Audio Routing
- **Removed Services:** `lib/services/proximity_service.dart`.
- **Removed Platform Channels:** Custom `MethodChannel` integrations (`com.theawesomeray.tether/proximity`) targeting native Android sensors are fully removed.
- **Native Implementation:** `android/app/src/main/kotlin/com/theawesomeray/tether/MainActivity.kt` has been completely cleaned and contains no custom MethodChannels or custom Kotlin overrides anymore.

---

## 🔔 Notification System Discrepancies

Below is a detailed log of discrepancies between historical specs (such as `AGENTS.md`) and the current notification implementation:

| Metric | Older Specification / Assumption | Current Actual Implementation |
| :--- | :--- | :--- |
| **Call FCM Payload Type** | Designed as `type: 'call'` to wake up callee device. | Implemented as `type: 'call_ping'` (which is now hardcoded to exit early / be ignored). |
| **Call Signal Silent Handling** | FCM handler generates full-screen local notification. | Foreground & background FCM messaging loops explicitly drop call-related payloads (`type == 'call_ping' \|\| type == 'call_ended'` immediately calls `return;`). |
| **Notification Channels** | Existed two channels: `tether_updates_v1` (updates) and `tether_calls_v1` (max importance calls). | Only `tether_updates_v1` is created during `NotificationService.initialize()`. The calls channel is completely omitted. |
| **Outbound Data Payload Rules** | `FcmService.send()` constructs `isDataOnly` for background action types. | `isDataOnly` checks `type == 'call_ping' \|\| type == 'call_ended' \|\| type == 'ping'`, which do not generate user banners. |
| **Local Wake Locks** | Screen turns on via `showWhenLocked` + `turnScreenOn` in `AndroidManifest.xml` triggered by calling FCMs. | Inactive. Calling triggers are removed, and local notification display is restricted only to standard updates (`chat`, `poke`, `todo`). |
