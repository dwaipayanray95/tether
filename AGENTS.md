# Tether — AI Agent Reference

Private couples app for **Raayyy (Ray)** and **Aproo**.  
Flutter · Android · Firebase (Firestore + RTDB) · Opus audio relay  
Package: `com.theawesomeray.tether`

---

## ⚠️ Hard Rules — Read First

| Rule | Detail |
|------|--------|
| **Never push to GitHub** | Do not run `git push`, `git tag`, or `gh release create` unless the user explicitly asks in that message |
| **Never bump `pubspec.yaml` version** | Do not change `version:` in pubspec unless the user explicitly asks and confirms the number |
| **Never change `coupleId`** | It is always `'ray-aproo'` — hardcoded across Firestore paths |
| **Never change allowed emails** | `ray@redacted.invalid` = Ray, `aproo@redacted.invalid` = Aproo |
| **Name comparison is case-sensitive** | `fromName == 'Ray'` (capital R). Partner key strings are lowercase `'ray'` / `'aproo'` |
| **Always run `flutter analyze` before committing** | Fix all errors and warnings first |

---

## Project Structure

```
lib/
├── main.dart                    # App entry point: Firebase init, initOpus (Opus FFI load), auth gate
├── config/
│   └── notification_config.dart # FCM service account credentials (private)
├── models/
│   ├── message_model.dart       # Message (id, text, fromUid, fromName, sentAt, readBy, reactions, replyTo*)
│   ├── todo_model.dart          # TodoItem (id, title, done, createdBy, createdAt)
│   ├── comment_model.dart       # Comment on todos
│   └── user_model.dart          # Basic user data
├── screens/
│   ├── main_shell.dart          # Root scaffold: bottom nav, incoming call listener, update check
│   ├── home_screen.dart         # Home tab: distance card, poke, quick actions (Chat/Todo/Call)
│   ├── chat_screen.dart         # Chat tab: paginated messages, search, reply, reactions, call button
│   ├── search_screen.dart       # Full-history message search overlay
│   ├── call_screen.dart         # Full-screen voice call UI (incoming & outgoing)
│   ├── todo_screen.dart         # Shared to-do list
│   ├── login_screen.dart        # Google Sign-In gate
│   ├── settings_screen.dart     # App version (dynamic), sign out, diagnostics link
│   ├── diagnostics_screen.dart  # Log viewer (enable/disable logging, view/clear logs)
│   └── location_screen.dart     # Partner location map
├── services/
│   ├── auth_service.dart        # Firebase Auth + Google Sign-In; isRay, myName, partnerName
│   ├── firestore_service.dart   # All Firestore reads/writes (messages, todos, presence, poke, unread)
│   ├── call_service.dart        # Firestore call signalling (status only — no SDP/ICE)
│   ├── audio_relay_service.dart # Bidirectional voice via Firebase RTDB + Opus FFI encode/decode
│   ├── fcm_service.dart         # Sends FCM via HTTP v1 API with service-account JWT (no Cloud Functions)
│   ├── notification_service.dart# FCM receive handling, local notifications, full-screen call alert
│   ├── proximity_service.dart   # Android PROXIMITY_SCREEN_OFF_WAKE_LOCK via MethodChannel
│   ├── location_service.dart    # Geolocator + Firestore location upload/stream
│   ├── update_service.dart      # GitHub Releases API check + APK download & install
│   ├── log_service.dart         # File-based debug logging (toggled in Settings/Diagnostics)
│   └── nav_service.dart         # Global navigatorKey for navigation from outside widget tree
├── theme/
│   └── app_theme.dart           # Colours, typography, component themes (coral #E8715A palette)
└── widgets/
    └── update_dialog.dart       # Two-dialog update flow: release notes → download progress
```

```
android/
└── app/src/main/kotlin/com/theawesomeray/tether/
    └── MainActivity.kt          # MethodChannel 'com.theawesomeray.tether/proximity'
                                 # Methods: acquire, release (proximity wake lock)
                                 #          setSpeakerOn(bool) (AudioManager speaker routing)
```

---

## Firestore Schema

All couple data lives under `couples/ray-aproo/`.

```
couples/ray-aproo/
  ├── messages/{msgId}
  │     text, fromUid, fromName, sentAt, readBy[], readTimes{uid→ts},
  │     reactions{emoji→[uid]}, replyToId?, replyToText?, imageUrl?
  ├── calls/{callId}
  │     callerName, status ('ringing'|'active'|'ended'), createdAt
  │     (no SDP, no ICE candidates — audio goes via RTDB, not WebRTC)
  ├── todos/{todoId}
  │     title, done, createdBy, createdAt, comments[]
  ├── pokes/status
  │     lastFrom (uid), fromName, sentAt
  ├── fcmTokens/
  │     ray    { token }
  │     aproo  { token }
  └── presence
        ray   { isOnline, lastSeen }
        aproo { isOnline, lastSeen }
```

---

## Firebase Realtime Database Schema

Audio data for active calls. Deleted automatically when call ends.

```
audio_relay/
  {callId}/
    ray/
      chunks/{pushId}
        d:  base64-encoded Opus packet (20ms frame, VoIP mode, 16kHz mono)
        ts: server timestamp
    aproo/
      chunks/{pushId}
        d:  base64-encoded Opus packet
        ts: server timestamp
```

- Each push key is chronologically sortable → `onChildAdded` delivers in order
- Deleted on `stop()` via `_db.ref('audio_relay/$callId').remove()`

---

## Audio Relay Call Architecture

```
Caller (Ray)                           Callee (Aproo)
────────────                           ──────────────
CallService.startCall()
  └─► Firestore calls/{id}
        callerName, status:'ringing'
        FcmService.send(type:'call')
                                       FCM received (background)
                                       → full-screen local notification
                                       User taps → app opens
                                       MainShell._openIncomingCallScreen()
                                       CallScreen shows (incomingRing state)
                                       User taps Accept
                                       CallService.acceptCall()
                                         → status:'active'

status:'active' seen by caller
AudioRelayService.start(callId, 'ray', 'aproo')
  → recorder → PCM16 → Opus encode    AudioRelayService.start(callId, 'aproo', 'ray')
  → base64 → RTDB push                  → recorder → PCM16 → Opus encode
                                          → base64 → RTDB push

RTDB onChildAdded (aproo/chunks)      RTDB onChildAdded (ray/chunks)
→ Opus decode → PCM16                 → Opus decode → PCM16
→ feedFromStream → speaker            → feedFromStream → speaker

Hang up: CallService.endCall()        Firestore status:'ended'
         FcmService.send(call_ended)  → CallScreen._hangUp(remote:true)
         RTDB audio_relay removed
```

---

## Feature Map — What to Edit for Common Changes

### 💬 Chat / Messages
| Change | Files |
|--------|-------|
| Message bubble appearance | `chat_screen.dart` → `_MessageBubble` widget (bottom of file) |
| Timestamp format | `chat_screen.dart` → `_formatTimestamp()` |
| Pagination (page size, load-more trigger) | `chat_screen.dart` → `_loadInitialMessages()`, `_loadMore()` |
| Scroll-to-message / highlight | `chat_screen.dart` → `scrollToMessageById()` |
| Reply behaviour | `chat_screen.dart` → `_replyTo` state + `_buildInput()` |
| Reactions | `chat_screen.dart` → `_ReactionPicker`, `_MessageBubble.onReaction` |
| Unread badge | `firestore_service.dart` → `unreadCountStream()`, `markMessagesRead()` |
| Message search | `search_screen.dart` + `firestore_service.dart` → `getAllMessages()` |
| Sending images | `chat_screen.dart` → `_pickAndSendImage()` |
| Firestore message read/write | `firestore_service.dart` → `messageStream()`, `sendMessage()`, `fetchMessagePage()` |

### 📞 Voice Calls
| Change | Files |
|--------|-------|
| Call UI (accept/decline/mute/speaker) | `call_screen.dart` |
| Ringtone (incoming ring) | `call_screen.dart` → `_startRingtone()` / `_stopRingtone()` (uses `flutter_ringtone_player`) |
| Audio relay start/stop | `audio_relay_service.dart` → `start()` / `stop()` |
| Audio codec (Opus, 20ms frames, VoIP mode) | `audio_relay_service.dart` — uses `opus_dart` `StreamOpusEncoder/Decoder` |
| Audio bitrate / frame size | `audio_relay_service.dart` → `StreamOpusEncoder.bytes(frameTime: FrameTime.ms20, ...)` |
| Speaker / earpiece routing | `audio_relay_service.dart` → `setSpeakerOn()` → MethodChannel → `MainActivity.kt` → `AudioManager.isSpeakerphoneOn` |
| Mute | `audio_relay_service.dart` → `setMuted()` — stops RTDB writes but keeps encoding |
| RTDB audio data path | `audio_relay_service.dart` → `_db.ref('audio_relay/$callId/$key/chunks')` |
| Firestore call signalling | `call_service.dart` — `startCall()`, `acceptCall()`, `endCall()`, `callStatusStream()` |
| Outgoing call flow | `call_screen.dart` → `_start()` (isOutgoing path) + `_watchCallStatus()` |
| Incoming call flow | `call_screen.dart` → `_start()` (incoming path) + `_acceptCall()` |
| Incoming call detection (foreground) | `main_shell.dart` → `_listenIncomingCalls()` via `CallService.incomingCallStream()` |
| Proximity sensor (screen off on ear) | `proximity_service.dart` + `MainActivity.kt` |
| Full-screen call notification (background/locked) | `notification_service.dart` → `firebaseMessagingBackgroundHandler` |
| Lock screen display of notification | `android/app/src/main/AndroidManifest.xml` → `showWhenLocked` + `turnScreenOn` on MainActivity |
| Call FCM send | `call_service.dart` → `startCall()` → `FcmService.send(type:'call', ...)` |
| Call-ended FCM (dismiss partner notification) | `call_screen.dart` → `_hangUp()` → `FcmService.send(type:'call_ended', ...)` |

### 🏠 Home Screen
| Change | Files |
|--------|-------|
| Distance card | `home_screen.dart` → `_buildDistanceCard()` |
| Online / last seen | `home_screen.dart` → `_buildLastSeen()` + `firestore_service.dart` → `presenceStream()` |
| Poke | `home_screen.dart` → `_sendPoke()` + `firestore_service.dart` → `sendPoke()` |
| Quick action tiles (Chat/Todo/Call) | `home_screen.dart` → `_buildQuickActions()` |
| Greeting / header | `home_screen.dart` → `_buildHeader()` |

### 🔔 Notifications
| Change | Files |
|--------|-------|
| Sending a push | `fcm_service.dart` → `send()` — uses HTTP v1, service-account JWT |
| FCM credentials | `config/notification_config.dart` |
| Foreground notification display | `notification_service.dart` → `FirebaseMessaging.onMessage` listener |
| Background notification display | `notification_service.dart` → `firebaseMessagingBackgroundHandler` |
| Notification channels | `notification_service.dart` → `_defaultChannel`, `_callChannel` |
| Notification tap → navigation | `notification_service.dart` → `_navigateFromPayload()` |
| Pending navigation in MainShell | `main_shell.dart` → `_handlePendingNotification()` |

### 🔄 Auto-Update
| Change | Files |
|--------|-------|
| GitHub release check | `update_service.dart` → `checkForUpdate()` |
| Download + install APK | `update_service.dart` → `downloadAndInstall()` |
| Update check frequency | `main_shell.dart` → `_checkForUpdate()` (30-min cooldown) |
| Release notes dialog UI | `widgets/update_dialog.dart` → `_ReleaseNotesDialog` |
| Download progress dialog UI | `widgets/update_dialog.dart` → `_DownloadDialog` |

### 📍 Location
| Change | Files |
|--------|-------|
| Location upload / stream | `location_service.dart` |
| Force-refresh ping partner | `location_service.dart` → `pingPartner()` |
| Location map view | `location_screen.dart` |

### ⚙️ Settings / Diagnostics
| Change | Files |
|--------|-------|
| App version display | `settings_screen.dart` — reads from `PackageInfo.fromPlatform()`, never hardcode |
| Debug logging toggle | `settings_screen.dart` + `log_service.dart` |
| Log viewer | `diagnostics_screen.dart` |

---

## Key Constants (Never Change)

```dart
// auth_service.dart
const coupleId = 'ray-aproo';
const allowedEmails = ['ray@redacted.invalid', 'aproo@redacted.invalid'];

// Auth helpers
AuthService().isRay       // true if current user is Ray
AuthService().myName      // 'Ray' or 'Aproo'  (capital first letter)
AuthService().partnerName // opposite of myName

// Presence / FCM token keys (lowercase)
'ray'   // Ray's key in Firestore presence + fcmTokens + RTDB audio paths
'aproo' // Aproo's key

// Notification channels
'tether_updates_v1'  // default channel (messages, pokes, todos)
'tether_calls_v1'    // incoming call channel (max importance, fullScreenIntent)

// Audio relay RTDB path
'audio_relay/{callId}/{ray|aproo}/chunks'  // Opus packets during active calls

// MethodChannel
'com.theawesomeray.tether/proximity'  // acquire, release, setSpeakerOn
```

---

## Colour Palette (`app_theme.dart`)

```dart
AppTheme.primary       // #E8715A  warm coral — primary buttons, icons, accents
AppTheme.primaryLight  // #FFF0EE  light coral — backgrounds for tinted tiles
AppTheme.secondary     // #B5838D  muted rose
AppTheme.background    // #FAF8F6  warm off-white scaffold
AppTheme.surface       // #FFFFFF  cards, bubbles
AppTheme.textDark      // #2D2D2D
AppTheme.textMuted     // #9E9E9E
AppTheme.divider       // #F0EDED
```

Fonts: **DM Sans** (body), **Playfair Display** (headings, hero text).

---

## Android Native (`MainActivity.kt`)

Single MethodChannel: `com.theawesomeray.tether/proximity`

| Method | Argument | What it does |
|--------|----------|--------------|
| `acquire` | — | Acquires `PROXIMITY_SCREEN_OFF_WAKE_LOCK` (screen dims on ear) |
| `release` | — | Releases the proximity wake lock |
| `setSpeakerOn` | `Boolean` | Sets `AudioManager.isSpeakerphoneOn` for call speaker routing |

Called by `ProximityService` (acquire/release) and `AudioRelayService.setSpeakerOn()`.

If you need another platform channel, add it to `MainActivity.kt` following the same pattern.

---

## FCM Send Rules

- **All notification sends go through `FcmService.send()`** — never call the FCM API directly
- `type: 'call'` → **data-only** — background handler shows full-screen local notification
- `type: 'call_ended'` → **data-only** — background/foreground handler cancels the call notification by ID (`callId.hashCode`)
- `type: 'chat'|'poke'|'todo'` → includes `notification` field for auto-display
- `type: 'ping'` → data-only — triggers partner location upload
- Partner name for FCM routing: `AuthService().partnerName.toLowerCase()` → `'ray'` or `'aproo'`
- FCM tokens stored at: `couples/ray-aproo/fcmTokens/{ray|aproo}/token`

---

## Logging

`LogService.log(message)` — writes to file only when logging is enabled in Settings → Diagnostics.  
Add log calls for any significant state change, network call, or user action.  
**Do not log sensitive data** (tokens, passwords).

Audio relay logs use the `[AudioRelay]` prefix for easy filtering in Diagnostics.
