# Tether — AI Agent Reference

Private couples app for **Raayyy (Ray)** and **Aproo**.  
Flutter · Android · Firebase (Firestore + RTDB) · Google Maps  
Package: `com.theawesomeray.tether`

---

## ⚠️ Hard Rules — Read First

| Rule | Detail |
|------|--------|
| **Never push to GitHub** | Do not run `git push`, `git tag`, or `gh release create` unless the user explicitly asks in that message |
| **Always bump `pubspec.yaml` version to +0.1.0 unless the user explicitly asks to set a specific version** |
| **Never change `coupleId`** | It is always `'ray-aproo'` — hardcoded across Firestore paths |
| **Never change allowed emails** | `dwaipayanray95@gmail.com` = Ray, `apoo.0404@gmail.com` = Aproo |
| **Name comparison is case-sensitive** | `myName == 'Ray'` (capital R). Partner key strings are lowercase `'ray'` / `'aproo'` |
| **Always run `flutter analyze` before committing** | Fix all errors and warnings first |
| **Calls are removed** | There is no call system. Do not reference `call_service.dart`, `audio_relay_service.dart`, `proximity_service.dart`, or `opus_dart` — these files do not exist |

---

## Project Structure

> Documentation is now modularized in the `.context` directory. See [index.md](file:///Users/rayr/tether/.context/index.md) for detailed sections: [hard-rules.md](file:///Users/rayr/tether/.context/hard-rules.md), [project-structure.md](file:///Users/rayr/tether/.context/project-structure.md), [feature-map.md](file:///Users/rayr/tether/.context/feature-map.md), [key-constants.md](file:///Users/rayr/tether/.context/key-constants.md), [database-schemas.md](file:///Users/rayr/tether/.context/database-schemas.md), [removed-features.md](file:///Users/rayr/tether/.context/removed-features.md).

```
lib/
├── main.dart                    # App entry point: Firebase init, auth gate, NotificationService.init
├── config/
│   └── notification_config.dart # FCM service account credentials (private — never log or print)
├── models/
│   ├── message_model.dart       # Message (id, senderId, text, type, imageUrl, sentAt, readBy,
│   │                            #   readTimes, reactions, replyToId?, replyToText?)
│   │                            # MessageType enum: text | image | poke
│   ├── todo_model.dart          # TodoItem (id, title, details?, isDone, createdBy, createdAt,
│   │                            #   dueDate?, assignedTo?, priority?, completedAt?, checklist[])
│   │                            # ChecklistItem (id, title, isDone)
│   │                            # Priority strings: 'low' | 'medium' | 'high'
│   │                            # assignedTo: 'ray' | 'aproo' | null (= Both)
│   ├── comment_model.dart       # TodoComment (id, text, authorName, createdAt)
│   └── user_model.dart          # TetherUser (uid, name, email, photoUrl?, partnerId?,
│                                #   togetherSince?)
├── screens/
│   ├── main_shell.dart          # Root scaffold: bottom nav (Home/Chat/Todo), update check,
│   │                            #   pending notification handler
│   ├── home_screen.dart         # Home tab — see § Home Screen section below (2278 lines)
│   ├── chat_screen.dart         # Chat tab: paginated messages, reply, reactions, image send
│   ├── search_screen.dart       # Full-history message search overlay (launched from HomeScreen header)
│   ├── todo_screen.dart         # Shared to-do list with priority, assignment, due date, checklist
│   ├── login_screen.dart        # Google Sign-In gate
│   ├── settings_screen.dart     # App version (dynamic), sign out, diagnostics link
│   ├── diagnostics_screen.dart  # Log viewer: enable/disable logging, view/clear log file
│   └── location_screen.dart     # Full-screen Google Map showing both users' pins + bottom info card
├── services/
│   ├── auth_service.dart        # Firebase Auth + Google Sign-In
│   │                            # isRay, myName, myDisplayName, partnerName, partnerDisplayName
│   ├── firestore_service.dart   # All Firestore reads/writes:
│   │                            #   messages, todos, presence, poke, sticky notes, locations
│   ├── fcm_service.dart         # Sends FCM via HTTP v1 API with RSA-signed service-account JWT
│   │                            #   Caches access token in memory (expires 5 min early)
│   ├── notification_service.dart# FCM receive (foreground + background isolate),
│   │                            #   local notifications, todo reminders (scheduleTodoReminder,
│   │                            #   syncTodoNotifications), chatIsOpen flag
│   ├── location_service.dart    # Geolocator + geocoding + Firestore upload
│   │                            #   updateIfNeeded() — throttled (>100m OR >10min)
│   │                            #   forceUpload() — immediate upload
│   │                            #   pingPartner() — sends FCM type:'ping' to trigger partner upload
│   ├── music_sync_service.dart  # MethodChannel 'com.theawesomeray.tether/music'
│   │                            #   Listens for onMusicChanged from native MediaSession
│   │                            #   updateMusicManually(), clearMusic()
│   │                            #   Deduplicates writes if track/artist/isPlaying unchanged
│   ├── update_service.dart      # GitHub Releases API check + APK download & install via OpenFile
│   ├── log_service.dart         # File-based debug logging to app_logs.txt
│   │                            #   Controlled by SharedPreferences 'logging_enabled'
│   └── nav_service.dart         # Global navigatorKey for navigation from outside widget tree
├── theme/
│   └── app_theme.dart           # Colours, typography, Material 3 component themes (coral palette)
└── widgets/
    └── update_dialog.dart       # Two-dialog update flow: _ReleaseNotesDialog → _DownloadDialog
```

```
android/
└── app/src/main/kotlin/com/theawesomeray/tether/
    └── MainActivity.kt          # Two MethodChannels:
                                 #
                                 # 'com.theawesomeray.tether/proximity'
                                 #   (legacy name — currently used for compass only if needed)
                                 #
                                 # 'com.theawesomeray.tether/music'
                                 #   EventChannel: fires onMusicChanged {track, artist, isPlaying}
                                 #   when the system MediaSession changes
```

---

## Home Screen — Feature Inventory

`home_screen.dart` is the largest file in the project (2278 lines / ~84 KB).  
It contains all of the following UI sections and their state logic:

| Section | Builder method | What it does |
|---------|---------------|--------------|
| **Header** | `_buildHeader()` | Greeting, "Raayyy & Aproo" title, partner online/last-seen dot, search & settings buttons |
| **Compass / Distance card** | `_buildCompassCard()` | Rotating bearing arrow → partner, distance headline, locality name, partner battery chip, partner music chip. Switches to green RADAR ACTIVE mode when proximity radar is on |
| **Sticky Notes Board** | `_buildStickyNotesBoard()` | Horizontally scrollable PostIt-style notes. Add, archive, restore, delete. Stored in Firestore `stickyNotes/{id}` |
| **Music Card** | `_buildMusicCard()` | Shows partner's now-playing track with rotating vinyl + audio visualizer. Shows your own sharing status. Manual share via dialog. Stop button via `MusicSyncService.clearMusic()` |
| **Poke Card** | `_buildPokeCard()` | Single-tap poke with 3-second cooldown and double haptic |
| **Quick Actions** | `_buildQuickActions()` | Two tiles: To-do (tab 2) and Chat (tab 1) |

### Proximity Radar (RTDB AirTag mode)
Auto-activates when distance ≤ 150 m OR partner has radar active.  
Uses Firebase RTDB path `proximity_sync/ray-aproo/{ray|aproo}` for 3 Hz lat/lng writes.  
The compass arrow updates at 50 ms intervals in radar mode vs 300 ms in normal mode.  
Pulls device compass heading from EventChannel `com.theawesomeray.tether/compass`.

---

## Firestore Schema

All couple data lives under `couples/ray-aproo/`.

```
couples/ray-aproo/
  ├── messages/{msgId}
  │     senderId, text, type ('text'|'image'|'poke'),
  │     imageUrl?, sentAt, readBy[], readTimes{uid→ts},
  │     reactions{emoji→[uid]}, replyToId?, replyToText?
  ├── todos/{todoId}
  │     title, details?, isDone, createdBy, createdAt,
  │     dueDate?, assignedTo? ('ray'|'aproo'|null),
  │     priority? ('low'|'medium'|'high'), completedAt?,
  │     checklist[] {id, title, isDone},
  │     comments[] {id, text, authorName, createdAt}
  ├── stickyNotes/{noteId}
  │     text, createdBy, createdAt, isArchived
  ├── pokes/status
  │     lastFrom (uid), fromName, sentAt
  ├── fcmTokens/
  │     ray    { token }
  │     aproo  { token }
  └── presence  (single document)
        ray   { isOnline, lastSeen, music{track,artist,isPlaying}?,
                battery{level,isCharging}? }
        aproo { isOnline, lastSeen, music{...}?, battery{...}? }
```

```
couples/ray-aproo/locations/{ray|aproo}
  lat, lng, locality?, updatedAt, name
```

---

## Firebase Realtime Database Schema

Used only for proximity radar. No audio relay data.

```
proximity_sync/
  ray-aproo/
    ray/
      lat, lng, active (bool), updatedAt (server timestamp)
    aproo/
      lat, lng, active (bool), updatedAt (server timestamp)
```

---

## Feature Map — What to Edit for Common Changes

### 💬 Chat / Messages
| Change | Files |
|--------|-------|
| Message bubble appearance | `chat_screen.dart` → `_MessageBubble` widget |
| Timestamp format | `chat_screen.dart` → `_formatTimestamp()` |
| Pagination (page size, load-more trigger) | `chat_screen.dart` → `_loadInitialMessages()`, `_loadMore()` |
| Scroll-to-message / highlight | `chat_screen.dart` → `scrollToMessageById()` |
| Reply behaviour | `chat_screen.dart` → `_replyTo` state + `_buildInput()` |
| Reactions | `chat_screen.dart` → `_ReactionPicker`, `_MessageBubble.onReaction` |
| Unread badge | `firestore_service.dart` → `unreadCountStream()`, `markMessagesRead()` |
| Message search | `search_screen.dart` + `firestore_service.dart` → `getAllMessages()` |
| Sending images | `chat_screen.dart` → `_pickAndSendImage()` |
| Firestore message read/write | `firestore_service.dart` → `messageStream()`, `sendMessage()`, `fetchMessagePage()` |
| MessageType values | `message_model.dart` → `MessageType` enum (text, image, poke) |

### 🏠 Home Screen
| Change | Files |
|--------|-------|
| Compass / distance card | `home_screen.dart` → `_buildCompassCard()` |
| Proximity radar (RTDB 3 Hz mode) | `home_screen.dart` → `_startProximityRadar()`, `_stopProximityRadar()`, `_checkProximityRadar()` |
| Compass sensor heading | `home_screen.dart` → `_initCompass()` (EventChannel `com.theawesomeray.tether/compass`) |
| Sticky notes add/archive/delete | `home_screen.dart` → `_buildStickyNotesBoard()`, `_showStickyArchiveSheet()` |
| Music card (now playing) | `home_screen.dart` → `_buildMusicCard()` |
| Music manual share dialog | `home_screen.dart` → `_showManualMusicDialog()` |
| Poke | `home_screen.dart` → `_sendPoke()` + `firestore_service.dart` → `sendPoke()` |
| Quick action tiles | `home_screen.dart` → `_buildQuickActions()` |
| Partner online / last seen | `home_screen.dart` → `_buildHeader()` + `firestore_service.dart` → `presenceStream()` |
| Partner battery display | `home_screen.dart` → `_buildCompassCard()` battery chip block |
| Partner music in compass chip | `home_screen.dart` → `_buildCompassCard()` music chip block |
| Force location refresh / ping | `home_screen.dart` → `_forceRefresh()` → `LocationService.pingPartner()` |

### ✅ To-do
| Change | Files |
|--------|-------|
| Todo list UI | `todo_screen.dart` |
| Todo model fields | `todo_model.dart` → `TodoItem`, `ChecklistItem` |
| Firestore todo read/write | `firestore_service.dart` → `todoStream()`, `addTodo()`, `updateTodo()`, `deleteTodo()` |
| Due date reminders | `notification_service.dart` → `scheduleTodoReminder()`, `syncTodoNotifications()` |

### 🔔 Notifications
| Change | Files |
|--------|-------|
| Sending a push | `fcm_service.dart` → `send()` — uses HTTP v1, RSA service-account JWT |
| FCM credentials | `config/notification_config.dart` |
| Foreground notification display | `notification_service.dart` → `FirebaseMessaging.onMessage` listener |
| Background notification display | `notification_service.dart` → `firebaseMessagingBackgroundHandler` |
| Notification channels | `notification_service.dart` → `_defaultChannel` (`tether_updates_v1`) |
| Notification tap → navigation | `notification_service.dart` → `_navigateFromPayload()` |
| Pending navigation in MainShell | `main_shell.dart` → `_handlePendingNotification()` |

### 📍 Location
| Change | Files |
|--------|-------|
| Location upload / stream | `location_service.dart` |
| Force-refresh / ping partner | `location_service.dart` → `pingPartner()` |
| Full-screen location map | `location_screen.dart` — opened via FAB or deep link (not in bottom nav) |
| Firestore location path | `couples/ray-aproo/locations/{ray|aproo}` |

### 🎵 Music Sync
| Change | Files |
|--------|-------|
| Auto-detect now playing (native) | `music_sync_service.dart` + `MainActivity.kt` EventChannel `com.theawesomeray.tether/music` |
| Manual track share | `home_screen.dart` → `_showManualMusicDialog()` → `MusicSyncService.updateMusicManually()` |
| Stop sharing | `MusicSyncService.clearMusic()` |
| Presence field for music | `firestore_service.dart` → `updateMusicPresence()` writes to `presence` doc |

### 🔄 Auto-Update
| Change | Files |
|--------|-------|
| GitHub release check | `update_service.dart` → `checkForUpdate()` |
| Download + install APK | `update_service.dart` → `downloadAndInstall()` |
| Update check frequency | `main_shell.dart` → `_checkForUpdate()` (30-min cooldown) |
| Release notes dialog UI | `widgets/update_dialog.dart` → `_ReleaseNotesDialog` |
| Download progress dialog UI | `widgets/update_dialog.dart` → `_DownloadDialog` |

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
const allowedEmails = ['dwaipayanray95@gmail.com', 'apoo.0404@gmail.com'];

// Auth helpers
AuthService().isRay            // true if current user is Ray
AuthService().myName           // 'Ray' or 'Aproo'  (capital first letter)
AuthService().myDisplayName    // display-friendly name
AuthService().partnerName      // opposite of myName
AuthService().partnerDisplayName

// Presence / FCM token / location keys (lowercase)
'ray'   // Ray's key in Firestore presence + fcmTokens + locations
'aproo' // Aproo's key

// Notification channel
'tether_updates_v1'  // single channel for all notifications (messages, pokes, todos)

// RTDB proximity sync path
'proximity_sync/ray-aproo/{ray|aproo}'  // lat, lng, active, updatedAt

// MethodChannels / EventChannels
'com.theawesomeray.tether/music'    // EventChannel — onMusicChanged from native MediaSession
'com.theawesomeray.tether/compass'  // EventChannel — device compass heading (double, degrees)
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

Two channels currently used:

| Channel | Type | Direction | What it does |
|---------|------|-----------|--------------|
| `com.theawesomeray.tether/music` | EventChannel | Native → Flutter | Fires `onMusicChanged` map `{track, artist, isPlaying}` when system MediaSession changes |
| `com.theawesomeray.tether/compass` | EventChannel | Native → Flutter | Streams device compass heading as `double` (degrees, 0–360) |

To add a new platform channel, follow the existing `EventChannel` / `MethodChannel` pattern in `MainActivity.kt`.

---

## FCM Send Rules

- **All notification sends go through `FcmService.send()`** — never call the FCM API directly
- `type: 'chat'` → includes `notification` field for auto-display; navigates to Chat tab on tap
- `type: 'poke'` → includes `notification` field; navigates to Home tab on tap
- `type: 'todo'` → includes `notification` field; navigates to Todo tab on tap
- `type: 'ping'` → **data-only** — triggers partner `LocationService.forceUpload()`
- Partner key for FCM token lookup: `AuthService().partnerName.toLowerCase()` → `'ray'` or `'aproo'`
- FCM tokens stored at: `couples/ray-aproo/fcmTokens/{ray|aproo}/token`
- Access token: RSA-signed JWT, cached in memory, regenerated 5 min before expiry

---

## Logging

`LogService.log(message)` — writes to `app_logs.txt` only when logging is enabled in Settings → Diagnostics.  
Add log calls for any significant state change, network call, or user action.  
**Do not log sensitive data** (tokens, passwords, location coordinates).
