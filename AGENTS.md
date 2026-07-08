# Tether — AI Agent Reference

Private couples app for **Raayyy (Ray)** and **Aproo**.  
Flutter · Android · Firebase (Firestore + RTDB) · Google Maps  
Package: `com.theawesomeray.tether`

---

## ⚠️ Hard Rules — Read First

| Rule | Detail |
|------|--------|
| **Never push to GitHub** | Do not run `git push`, `git tag`, or `gh release create` unless the user explicitly asks in that message |
| **Never bump version numbers** | Do not change `pubspec.yaml` version. The user will manage versioning manually |
| **Never change `coupleId`** | It is always `'ray-aproo'` — hardcoded across Firestore paths |
| **Never change allowed emails** | Two real personal Gmail addresses, defined in the gitignored `lib/config/env_config.dart` (`EnvConfig.allowedEmails[0]` = Ray, `[1]` = Aproo). Never write the literal addresses anywhere else — see the secrets rule below |
| **Never hardcode API keys, secrets, or personal emails in source** | This repo is public. Any real key, credential, or personal email committed to a tracked file (code, manifests, docs, CI logs) is permanently visible in git history even after being "removed" later — history rewrites are destructive and not a substitute for not committing it in the first place. All secrets (Firebase service account, allowed emails, Maps API key, keystore) must be injected at CI build time via GitHub Actions secrets into gitignored files (`env_config.dart`, `notification_config.dart`) or Gradle manifest placeholders — see `.github/workflows/build-apk.yml`'s "Restore Keystore & Configuration Secrets" step for the existing pattern to extend, not replace |
| **Name comparison is case-sensitive** | `myName == 'Ray'` (capital R). Partner key strings are lowercase `'ray'` / `'aproo'` |
| **Always run `flutter analyze` before committing** | Fix all errors and warnings first |
| **Calls are removed** | There is no call system. Do not reference `call_service.dart`, `audio_relay_service.dart`, `proximity_service.dart`, or `opus_dart` — these files do not exist |
| **All backup logic goes through `BackupService`** | Never add a new ad-hoc `GoogleDriveService` call for backing up/restoring app data. Messages, todos, comments, sticky notes, profiles, the couple doc, an allowlisted set of app preferences, and Snaps (`BackupService._syncSnaps()`) are all synced together in one `runBackup()` cycle. Never make saving/downloading/deleting a Snap call Drive directly again — that reintroduces the per-action Google auth UI flash this architecture exists to avoid. See `.context/feature-map.md` → Backup section |
| **Never run Google Sign-In / Drive calls from a background isolate** | Confirmed broken: `attemptLightweightAuthentication()` requires a foreground Activity on Android and fails every time from a headless WorkManager Worker, even after `GoogleSignIn.instance.initialize()`. Backup triggers must run in the foreground (`ForegroundBackupScheduler.runIfDue()` on app open/resume) — do not reintroduce `workmanager` for this |
| **Never add a proactive/periodic Google scope-check** | Removed on purpose — it caused a visible Credential Manager UI flash on every app open. Scope validation is lazy/reactive only, handled in `GoogleDriveService._getAccessToken()` |

---

## Project Structure

> Documentation is now modularized in the `.context` directory. See [index.md](file:///Users/rayr/tether/.context/index.md) for detailed sections: [hard-rules.md](file:///Users/rayr/tether/.context/hard-rules.md), [project-structure.md](file:///Users/rayr/tether/.context/project-structure.md), [feature-map.md](file:///Users/rayr/tether/.context/feature-map.md), [key-constants.md](file:///Users/rayr/tether/.context/key-constants.md), [database-schemas.md](file:///Users/rayr/tether/.context/database-schemas.md), [removed-features.md](file:///Users/rayr/tether/.context/removed-features.md).

```
lib/
├── main.dart                    # App entry point: Firebase init, GoogleSignIn.initialize(), auth gate
├── config/
│   ├── notification_config.dart # FCM service account credentials (private — never log or print)
│   ├── env_config.dart          # Gitignored: allowedEmails, coupleId (restored via ENV_CONFIG_DART secret)
│   ├── google_scopes.dart       # GoogleScopes.basic (email, profile) / .drive (drive.file, drive.appdata) / .all
│   └── backup_config.dart       # BackupConfig — Drive file naming/rotation contract + backedUpPreferenceKeys
├── models/
│   ├── message_model.dart       # Message (id, senderId, text, type, imageUrl, audioUrl?, duration?, sentAt,
│   │                            #   readBy, readTimes, reactions, replyToId?, replyToText?)
│   │                            # MessageType enum: text | image | poke | voice
│   ├── todo_model.dart          # TodoItem (id, title, details?, isDone, createdBy, createdAt,
│   │                            #   dueDate?, assignedTo?, priority?, completedAt?, checklist[])
│   │                            # ChecklistItem (id, title, isDone)
│   │                            # Priority strings: 'low' | 'medium' | 'high'
│   │                            # assignedTo: 'ray' | 'aproo' | null (= Both)
│   ├── comment_model.dart       # TodoComment (id, text, authorName, createdAt) — stored as a SUBCOLLECTION
│   │                            #   at todos/{todoId}/comments/{commentId}, NOT an inline array
│   ├── user_model.dart          # TetherUser (uid, name, email, photoUrl?, partnerId?, togetherSince?)
│   ├── partner_profile_model.dart # PartnerProfile — birthday, clothingSizes{}, shoeSize?, ringSize?,
│   │                            #   allergies[], foodDislikes[], favoriteFoods[], favoriteColor?,
│   │                            #   favoriteMovies[] (max 5, `maxFavoriteMovies` const)
│   ├── backup_cursor_model.dart # BackupCursor — per-collection sync timestamps + last backup size/time
│   ├── backup_snapshot_model.dart # BackupSnapshot — decrypted backup content
│   └── deletion_record_model.dart # DeletionRecord — one tombstone entry
├── screens/
│   ├── main_shell.dart          # Root scaffold: bottom nav (Home/Chat/Todo), update check,
│   │                            #   pending notification handler, ForegroundBackupScheduler.runIfDue()
│   ├── home_screen.dart         # Home tab — now just 252 lines: header (greeting/presence/battery) +
│   │                            #   sticky-board header, composes the widgets/home/* below. See § Home Screen
│   ├── chat_screen.dart         # Chat tab: paginated messages, reply, reactions, image + voice send
│   ├── search_screen.dart       # Full-history message search overlay (launched from HomeScreen header)
│   ├── todo_screen.dart         # Shared to-do list with priority, assignment, due date, checklist
│   ├── login_screen.dart        # Google Sign-In gate
│   ├── partner_info_screen.dart # Tabbed "Me" / partner profile screen — see PartnerProfile model above
│   ├── gallery_screen.dart      # Full gallery of saved Snaps (local storage + Drive backup), delete w/ confirm
│   ├── settings_screen.dart     # App version (dynamic), sign out, diagnostics link, Backup tile
│   ├── diagnostics_screen.dart  # Log viewer + dev-only backup test harness (dropped once backup is stable)
│   └── backup_screen.dart       # User-facing Backup screen: "Backup Now", progress, last backup date/size
├── services/
│   ├── auth_service.dart        # Firebase Auth + Google Sign-In
│   │                            # isRay, myName, myDisplayName, partnerName, partnerDisplayName
│   │                            # getGoogleUser() — cached + in-flight-guarded attemptLightweightAuthentication()
│   ├── crypto_service.dart      # E2EE key pairs generation/exchange & AES-GCM data encryption
│   │                            #   getSharedKey() caches + in-flight-guards the ECDH+SHA-256 derivation
│   ├── voice_service.dart       # Encrypts Opus recording (via record) & local decrypt (via flutter_sound)
│   │                            #   Disposes/recreates AudioRecorder after every recording (Android reuse bug)
│   ├── firestore_service.dart   # All Firestore reads/writes:
│   │                            #   messages, todos, comments (subcollection), presence, poke, sticky notes,
│   │                            #   locations, deletion tombstones, backup delta-fetch/count queries
│   ├── fcm_service.dart         # Sends FCM via HTTP v1 API with RSA-signed service-account JWT
│   │                            #   Caches access token in memory (expires 5 min early)
│   ├── notification_service.dart# FCM receive (foreground + background isolate),
│   │                            #   local notifications, todo reminders (scheduleTodoReminder,
│   │                            #   syncTodoNotifications), chatIsOpen flag
│   ├── location_service.dart    # Geolocator + geocoding + Firestore upload
│   │                            #   updateIfNeeded() — throttled (>100m OR >10min)
│   │                            #   forceUpload() — immediate upload
│   │                            #   pingPartner() — sends FCM type:'ping' to trigger partner upload
│   ├── local_storage_service.dart # Local on-device Snap storage under getApplicationDocumentsDirectory()/snaps/
│   │                            #   (metadata as .json: caption, date, driveFileId); uploads Polaroid PNGs
│   │                            #   to Drive backup via GoogleDriveService after saving locally
│   ├── music_sync_service.dart  # MethodChannel 'com.theawesomeray.tether/music'
│   │                            #   Listens for onMusicChanged from native MediaSession
│   │                            #   updateMusicManually(), clearMusic()
│   │                            #   Deduplicates writes if track/artist/isPlaying unchanged
│   ├── update_service.dart      # GitHub Releases API check + APK download & install via OpenFile
│   ├── log_service.dart         # File-based debug logging to app_logs.txt
│   │                            #   Controlled by SharedPreferences 'logging_enabled'
│   ├── nav_service.dart         # Global navigatorKey for navigation from outside widget tree
│   ├── google_drive_service.dart # Drive REST calls: snap/key-backup uploads + generic named-file
│   │                            #   helpers (find/upload/download/rename/delete by name) used by BackupService
│   ├── backup_service.dart      # BackupService: runBackup()/restoreFromBackup()/inspect() — the
│   │                            #   unified backup pipeline (see § Backup System below)
│   ├── backup_merge.dart        # Pure merge/rotation logic — unit-tested, no network dependency
│   ├── backup_cursor_store.dart # SharedPreferences-backed BackupCursor persistence
│   └── foreground_backup_scheduler.dart # runIfDue() — 24h-throttled trigger from main_shell
├── theme/
│   └── app_theme.dart           # Colours, typography, Material 3 component themes (coral palette)
└── widgets/
    ├── home/
    │   ├── compass_card.dart        # Bearing/distance to partner, proximity radar, heart-pulse animation
    │   ├── music_card.dart          # Partner's now-playing track + vinyl rotation animation
    │   ├── poke_card.dart           # "Poke" mechanic — cooldown + haptic feedback
    │   ├── sticky_board.dart        # Pastel sticky notes board: add/archive/restore/delete + archive sheet
    │   ├── quick_snap.dart          # Last received Snap card — E2EE decrypt, full-screen Polaroid viewer
    │   ├── quick_actions.dart       # Quick-access row: To-do, unread Chat count, Partner Info
    │   └── profile_completion_bar.dart # Slim progress bar for the 9 PartnerProfile fields, hides at 9/9
    └── update_dialog.dart       # Two-dialog update flow: _ReleaseNotesDialog → _DownloadDialog
```

```
android/
└── app/src/main/kotlin/com/theawesomeray/tether/
    └── MainActivity.kt          # Three platform channels:
                                 #
                                 # 'com.theawesomeray.tether/music'    (MethodChannel)
                                 #   Native → Flutter one-way push via invokeMethod("onMusicChanged", data)
                                 #   {track, artist, isPlaying} — fired from a BroadcastReceiver on
                                 #   MediaSession changes. NOT an EventChannel, despite the name.
                                 #
                                 # 'com.theawesomeray.tether/battery'  (MethodChannel)
                                 #   Flutter → Native request/response: invokeMethod('getBatteryInfo')
                                 #   returns {batteryLevel: Int, isCharging: Bool}
                                 #
                                 # 'com.theawesomeray.tether/compass'  (EventChannel)
                                 #   Native → Flutter stream of device compass heading (double, 0-360)
```

---

## Home Screen — Feature Inventory

`home_screen.dart` was refactored from a 2278-line monolith down to **252 lines** —
it now only owns the header and sticky-board header, and composes seven separate
widgets from `lib/widgets/home/` for everything else. **When editing a home-screen
feature, go straight to the widget file below — do not look for `_build*()` methods
inside `home_screen.dart` itself for these.**

| Section | File | What it does |
|---------|------|--------------|
| **Header** | `home_screen.dart` | Greeting, partner online/last-seen dot, battery, search & settings buttons |
| **Sticky-board header** | `home_screen.dart` | "Our Sticky Board" title + archive button, above `StickyBoard` |
| **Profile completion bar** | `widgets/home/profile_completion_bar.dart` | Slim progress bar for the 9 `PartnerProfile` fields; hides itself once all 9 are filled. Tapping it opens `PartnerInfoScreen` |
| **Quick Snap** | `widgets/home/quick_snap.dart` | Last received Snap card, E2EE-decrypted; opens a full-screen Polaroid viewer with a button through to `GalleryScreen` |
| **Compass / Distance card** | `widgets/home/compass_card.dart` | Rotating bearing arrow → partner, distance headline, locality name, partner battery chip, partner music chip. Switches to green RADAR ACTIVE mode when proximity radar is on |
| **Sticky Notes Board** | `widgets/home/sticky_board.dart` | Horizontally scrollable PostIt-style notes. Add, archive, restore, delete. Stored in Firestore `sticky_notes/{id}` |
| **Music Card** | `widgets/home/music_card.dart` | Shows partner's now-playing track with rotating vinyl + audio visualizer. Shows your own sharing status. Manual share via dialog. Stop button via `MusicSyncService.clearMusic()` |
| **Poke Card** | `widgets/home/poke_card.dart` | Single-tap poke with 3-second cooldown and double haptic |
| **Quick Actions** | `widgets/home/quick_actions.dart` | Quick-access row: To-do tab, unread Chat count, Partner Info |

### Proximity Radar (RTDB AirTag mode)
Auto-activates when distance ≤ 150 m OR partner has radar active.  
Uses Firebase RTDB path `proximity_sync/ray-aproo/{ray|aproo}` for 3 Hz lat/lng writes.  
The compass arrow updates at 50 ms intervals in radar mode vs 300 ms in normal mode.  
Pulls device compass heading from EventChannel `com.theawesomeray.tether/compass`.

---

## Firestore Schema

Per-user data lives at the top level under `users/{uid}`; everything shared by the
couple lives under `couples/ray-aproo/`.

```
users/{uid}
  uid, name, email, photoUrl?, coupleId,
  profile { birthday?, clothingSizes{}, shoeSize?, ringSize?, allergies[],
            foodDislikes[], favoriteFoods[], favoriteColor?, favoriteMovies[] }
  -- see partner_profile_model.dart (PartnerProfile) for the `profile` map shape.
  -- `profile` is self-reported: each user only edits their own via
  -- partner_info_screen.dart's "Me" tab; the partner sees it read-only.
  -- NOTE: the E2EE public key is NOT here — it lives at
  -- couples/ray-aproo/status/presence.{ray|aproo}.publicKey (see below).
```

```
couples/ray-aproo/
  anniversary?: Timestamp   -- shared field, either partner can edit
  ├── messages/{msgId}
  │     senderId, text, type ('text'|'image'|'poke'|'voice'),
  │     imageUrl?, audioUrl?, duration?, sentAt, updatedAt, readBy[], readTimes{uid→ts},
  │     reactions{emoji→[uid]}, replyToId?, replyToText?
  ├── todos/{todoId}
  │     title, details?, isDone, createdBy, createdAt, updatedAt,
  │     dueDate?, assignedTo? ('ray'|'aproo'|null),
  │     priority? ('low'|'medium'|'high'), completedAt?,
  │     checklist[] {id, title, isDone}
  │     └── comments/{commentId}   -- SUBCOLLECTION, not an inline array
  │           text, authorName, createdAt
  ├── sticky_notes/{noteId}
  │     text, createdBy, createdByName, colorIndex, createdAt, updatedAt,
  │     isArchived, archivedAt?
  ├── pokes/status
  │     lastFrom (uid), fromName, sentAt
  ├── fcmTokens/
  │     ray    { token }
  │     aproo  { token }
  ├── deletions/{deletionId}
  │     collection ('todos' | 'sticky_notes' | 'todos/{todoId}/comments'),
  │     docId, deletedAt
  │     — tombstone log for the backup pipeline; see § Backup System
  └── presence  (single document)
        ray   { isOnline, lastSeen, publicKey? (E2EE, X25519 base64),
                music{track,artist,isPlaying}?, battery{level,isCharging}? }
        aproo { isOnline, lastSeen, publicKey?, music{...}?, battery{...}? }
```

```
couples/ray-aproo/locations/{ray|aproo}
  lat, lng, locality?, updatedAt, name
```

**Note:** `todos/{todoId}`, `messages/{msgId}`, and `sticky_notes/{noteId}` docs all
get `updatedAt: FieldValue.serverTimestamp()` set on every mutating write, not just
creation — required by the backup pipeline's incremental delta queries. `comments`
intentionally has no `updatedAt` (immutable after creation, only deletable — `createdAt`
is a valid delta cursor for them).

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
| MessageType values | `message_model.dart` → `MessageType` enum (text, image, poke, voice) |
| Voice notes / scrubbing | `chat_screen.dart` → `VoicePlaybackWidget` + `voice_service.dart` |
| Date timeline headers | `chat_screen.dart` → `buildDateHeader()` |
| E2EE pre-cache scrolls | `chat_screen.dart` → `_initSharedKey()` / caching `_sharedKey` |

### 🏠 Home Screen
`home_screen.dart` itself only owns the header + sticky-board header now — everything
else below is its own widget file under `lib/widgets/home/` (see § Home Screen — Feature
Inventory above for the full table). Quick pointers:

| Change | Files |
|--------|-------|
| Compass / distance card | `widgets/home/compass_card.dart` |
| Proximity radar (RTDB 3 Hz mode) | `widgets/home/compass_card.dart` — proximity radar start/stop/check logic lives here now |
| Sticky notes add/archive/delete | `widgets/home/sticky_board.dart` |
| Music card (now playing) | `widgets/home/music_card.dart` |
| Poke | `widgets/home/poke_card.dart` + `firestore_service.dart` → `sendPoke()` |
| Quick action tiles | `widgets/home/quick_actions.dart` |
| Quick Snap card + Polaroid viewer | `widgets/home/quick_snap.dart` → opens `gallery_screen.dart` |
| Profile completion bar | `widgets/home/profile_completion_bar.dart` → opens `partner_info_screen.dart` |
| Partner online / last seen | `home_screen.dart` header + `firestore_service.dart` → `presenceStream()` |
| Force location refresh / ping | `LocationService.pingPartner()` |

### 👤 Partner Info
| Change | Files |
|--------|-------|
| Profile fields (birthday/zodiac, sizes, allergies, favorites, movies) | `partner_info_screen.dart` + `partner_profile_model.dart` (`PartnerProfile`) |
| Anniversary (shared, either partner can edit) | `partner_info_screen.dart` anniversary card + `firestore_service.dart` → `updateAnniversary()` |
| Editable by owner / view-only for partner | `partner_info_screen.dart` — tabbed "Me" / partner view, edit sheets only shown on the "Me" tab |

### 📸 Snaps / Gallery
| Change | Files |
|--------|-------|
| Sending a Snap | `widgets/home/quick_snap.dart` |
| Local on-device storage | `local_storage_service.dart` (saves under `getApplicationDocumentsDirectory()/snaps/`) |
| Drive backup of Snap PNGs | `local_storage_service.dart` → `GoogleDriveService` upload after local save |
| Full gallery / delete | `gallery_screen.dart` |

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
| Firestore location path | `couples/ray-aproo/locations/{ray|aproo}` |

### 🎵 Music Sync
| Change | Files |
|--------|-------|
| Auto-detect now playing (native) | `music_sync_service.dart` + `MainActivity.kt` MethodChannel `com.theawesomeray.tether/music` (native pushes via `invokeMethod`, not an EventChannel) |
| Manual track share | `widgets/home/music_card.dart` → `_showManualMusicDialog()` → `MusicSyncService.updateMusicManually()` |
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

### 💾 Backup
| Change | Files |
|--------|-------|
| Orchestration (fetch delta → merge → encrypt → upload → verify → rotate → promote) | `backup_service.dart` → `runBackup()` |
| Restore (download + decrypt + merge with live Firestore) | `backup_service.dart` → `restoreFromBackup({dryRun})` |
| Pure merge/rotation logic (unit-tested, no network) | `backup_merge.dart` — extend `test/backup_merge_test.dart` here, not integration tests |
| Trigger cadence (24h, checked on app open/resume) | `foreground_backup_scheduler.dart` → `ForegroundBackupScheduler.runIfDue()`, called from `main_shell.dart` |
| Drive file naming / rotation contract / preferences allowlist | `backup_config.dart` (`BackupConfig`) |
| Local cursor persistence | `backup_cursor_model.dart` + `backup_cursor_store.dart` |
| Deletion tombstones | `firestore_service.dart` → `_recordDeletion()`, `deletionsSince()`, `pruneDeletionsBefore()` |
| Generic Drive file helpers (find/upload/download/rename/delete by name) | `google_drive_service.dart` |
| User-facing screen | `backup_screen.dart`, linked from `settings_screen.dart` |
| Dev-only manual test harness (dropped once feature is stable) | `diagnostics_screen.dart` → "Run Backup Now" / "Inspect Backup State" / "Restore Preview" / "Run Backup If Due" |
| E2EE key backup (separate — not part of this pipeline) | `main_shell.dart` → `_checkE2EESetup()` + `crypto_service.dart` + `google_drive_service.dart` → `backupKeyBackup()`/`restoreKeyBackup()` |

### ⚙️ Settings / Diagnostics
| Change | Files |
|--------|-------|
| App version display | `settings_screen.dart` — reads from `PackageInfo.fromPlatform()`, never hardcode |
| Debug logging toggle | `settings_screen.dart` + `log_service.dart` |
| Log viewer | `diagnostics_screen.dart` |

---

## Key Constants & Secrets (Gitignored & Restored via GitHub Secrets)

Sensitive variables like permitted emails, couple ID, and maps API Key are loaded from **`lib/config/env_config.dart`**. This file is gitignored. On GitHub Action runs, it is restored dynamically using the `ENV_CONFIG_DART` secret:

```dart
// lib/config/env_config.dart (Template / Default Values)
class EnvConfig {
  static const allowedEmails = ['your-email@example.com', 'partner-email@example.com'];
  static const coupleId = 'ray-aproo';
}
```

// Auth helpers
AuthService().isRay            // true if current user is Ray
AuthService().myName           // 'Ray' or 'Aproo'  (capital first letter)
AuthService().myDisplayName    // display-friendly name
AuthService().partnerName      // opposite of myName
AuthService().partnerDisplayName

---

## End-to-End Encryption (E2EE) Rules

Tether implements standard zero-trust E2EE using Elliptic Curve Diffie-Hellman (ECDH) key exchange and AES-GCM (256-bit) symmetric encryption.

* **Key Exchange (X25519)**: Devices generate keys on first launch.
  * Public keys are stored in Firestore under `/couples/ray-aproo/status/presence` -> `ray.publicKey` / `aproo.publicKey`.
  * Private keys are stored locally using `flutter_secure_storage`.
* **Shared Secret Derivation**: Derived using `MyPrivateKey + PartnerPublicKey` via ECDH, hashed with SHA-256.
* **Mandatory Architecture Rule**: **Every new feature added to the app MUST be end-to-end encrypted.** No personal data or user-generated text/media may be saved to Firestore in plain text.
* **Encrypted Fields**:
  * Messages: Stored in the `text` field as E2EE JSON strings.
  * Snaps: Cropped Base64 photo and caption are stored as E2EE JSON strings.
  * Voice Notes: Recorded Opus audio bytes are encrypted and stored in the message's `audioUrl` field as an E2EE JSON string.
  * Todos: Titles, details, and checklist items titles are stored as E2EE JSON strings.
  * Todo Comments: Comment text is stored as E2EE JSON strings.
  * Sticky Notes: Note text is stored as E2EE JSON strings.
* **Key Backup**:
  * Encrypted locally using a derived key from the user's 4-digit PIN (AES-256 + PBKDF2).
  * Saved to Google Drive as `tether_key_backup.json`.
  * Restored transparently during a clean reinstall by asking the user for their PIN.
* **Push Notifications**:
  * Because text payloads are encrypted, FCM push notifications are configured to only show generic text (e.g. `"Sent a message"`, `"New note left on task"`, `"📷 New Polaroid Snap!"`) to prevent leaking metadata.
* **Shared key caching**: `CryptoService.getSharedKey()` caches the derived key AND guards against concurrent callers with an in-flight `Future` (`_sharedKeyFuture`) — cold start fires many independent flows nearly simultaneously (E2EE check, backup-if-due, decrypting visible chat/comments) that all need this key. Without the in-flight guard each one redoes the expensive ECDH+SHA-256 derivation itself. If you ever see `"Crypto: Derived shared secret key successfully"` logged more than once per session, this guard has regressed.

// Presence / FCM token / location keys (lowercase)
'ray'   // Ray's key in Firestore presence + fcmTokens + locations
'aproo' // Aproo's key

// Notification channel
'tether_updates_v1'  // single channel for all notifications (messages, pokes, todos)

// RTDB proximity sync path
'proximity_sync/ray-aproo/{ray|aproo}'  // lat, lng, active, updatedAt

// MethodChannels / EventChannels
'com.theawesomeray.tether/music'    // MethodChannel — native invokeMethod('onMusicChanged', ...) push
'com.theawesomeray.tether/battery'  // MethodChannel — Flutter invokeMethod('getBatteryInfo') request/response
'com.theawesomeray.tether/compass'  // EventChannel — device compass heading (double, degrees)
```

---

## Backup System

A unified, incremental, encrypted backup pipeline — **do not add a separate ad-hoc
Drive backup for a new feature; extend this pipeline instead.**

* **What's covered**: todos, comments, messages, sticky notes, both partners'
  profiles, the couple doc, and an allowlisted set of app preferences
  (`BackupConfig.backedUpPreferenceKeys`). E2EE key backup (`tether_key_backup.json`)
  is intentionally separate.
* **Where it lives on Drive**: `Tether/latest_backup.json.enc` (current) +
  `Tether/backup_gen1/2/3.json.enc` (rotated prior generations — oldest deleted once
  a 4th would be created, `BackupConfig.maxBackupGenerations = 3`).
* **Encryption**: the whole snapshot is one JSON blob encrypted with the couple's
  shared E2EE key (`CryptoService.encryptBytes`/`decryptBytes`) — same key used for
  messages/voice notes. Individual fields already stored as E2EE ciphertext (message
  text, todo titles, etc.) are archived as-is, not double-encrypted.
* **Incremental fetch**: each collection is queried with
  `where updatedAt > cursor` (or `createdAt` for comments, which are immutable after
  creation) instead of re-reading the whole collection every run.
  `todos`/`messages`/`sticky_notes` all get `updatedAt` maintained on every mutating
  write for this to work — see § Firestore Schema.
* **Deletions**: cursor queries never see removals (a deleted doc just stops
  appearing). A tombstone log at `couples/ray-aproo/deletions/{id}` covers this —
  `deletionsSince()`/`pruneDeletionsBefore()` in `firestore_service.dart`.
* **Rotation is atomic**: a new backup is uploaded as `latest_backup.new.json.enc`,
  integrity-checked (`BackupService._verifyIntegrity` — backup counts must be ≥ live
  Firestore counts via cheap `.count()` aggregation queries), *then* prior generations
  are rotated and the new file promoted. A failed/interrupted run never corrupts the
  last known-good backup.
* **Trigger**: `ForegroundBackupScheduler.runIfDue()`, called from `main_shell.dart`
  on cold start and every `AppLifecycleState.resumed`. At most once per 24h, using
  the persisted `BackupCursor.lastBackupAt` — **not** a background scheduler (Google
  Sign-In's Drive auth doesn't work from a headless isolate on Android — confirmed by
  testing, see `.context/removed-features.md` #4).
* **Restore**: `BackupService.restoreFromBackup({dryRun})` downloads+decrypts the
  latest backup and merges it with whatever's currently live in Firestore (live wins
  conflicts). `dryRun: true` computes the same merge for inspection without touching
  the local cursor or applying preferences — used by the Diagnostics "Restore Preview".
* **Testing**: pure logic (`mergeDelta`, `applyTombstones`, `sanitizeForJson`,
  `maxTimestampField`, `computeRotationPlan`) lives in `backup_merge.dart` with zero
  network dependency — extend `test/backup_merge_test.dart` when changing this logic.
  Everything that touches live Firebase/Drive/E2EE is instead verified via the
  Diagnostics screen's manual test harness ("Run Backup Now" / "Inspect Backup State"
  / "Restore Preview" / "Run Backup If Due") — dev-only, will be dropped once the
  feature has proven stable in production.

---

## Local-First Architecture (in progress — see the plan)

**Goal**: chat/todo/sticky-note screens read from an on-device SQLite database
(via `drift`) instead of Firestore streams directly. Firestore stays a pure
real-time sync relay between the two partners' devices — it is never written
back to with recovered/old data. The Drive backup (above) remains the
permanent full-history archive, unchanged. Full design + phase breakdown:
`/Users/rayr/.claude/plans/delegated-zooming-lemur.md`.

Note: the 90-day Firestore purge this architecture is designed around does
**not exist yet** — confirmed during planning that no Cloud Function or
scheduled job purges anything anywhere in this repo. Building the local DB
is still worthwhile on its own merits (instant local search, offline reads);
the purge job itself is explicitly out of scope until the local-DB safety
net is proven trustworthy in production.

**Status:**
- ✅ **Phase 0 (scaffolding)**: `lib/local_db/` — `app_database.dart`
  (`AppDatabase`, opens `tether_local.sqlite` via `path_provider`) +
  `tables/{message,todo,comment,sticky_note}_table.dart`, mirroring each
  existing model's `toMap()`/`fromMap()` shape field-for-field (`sentAt`/
  `createdAt`/etc. stored as epoch millis for indexed sort; `updatedAt` is a
  local sync-cursor bookkeeping column with no model equivalent, same
  convention the backup pipeline already uses). Nothing reads/writes through
  it yet — zero behavior change.
- ✅ **Phase 1 (shadow mode)**: `local_sync_service.dart` (`LocalSyncService`)
  — live Firestore listeners for messages (windowed to 50, matching today's
  `messageStream()`, plus a message backfill via `fetchMessagesSince()`,
  incremental after the first run — see the cursor note below), todos/
  sticky-notes/comments
  (unlimited listeners, already full-history since those screens have no
  pagination today). `converters.dart` holds the pure Firestore-map→Drift-
  companion conversion functions (unit tested in
  `test/local_sync_merge_test.dart`, same convention as
  `backup_merge_test.dart`). Started fire-and-forget from `main_shell.dart`'s
  startup sequence. **Nothing reads from the local DB yet** — verify via
  Diagnostics → "Inspect Local DB" (compares local row counts against live
  Firestore `.count()`) before starting Phase 2. **Do not start Phase 2
  until this has been dogfooded on a real device and counts checked out** —
  that's the whole point of shipping this phase separately. **Verified**:
  1115 messages backfilled and confirmed matching live Firestore counts on
  a real device.
- ✅ **Phase 2 (chat_screen.dart cutover)**: pagination
  (`_loadInitialMessages`/`_loadMoreMessages`), the live top-50 window, and
  search (`_activateSearch`) all now read from `MessageDao` instead of
  Firestore directly. `_pageCursor` changed from a `DocumentSnapshot` to a
  plain `sentAt` epoch-millis int — covered by dedicated pagination-boundary
  tests in `test/message_dao_test.dart` (newest-first order, exclusive
  cursor, no skip/duplicate across pages) since this was flagged as the
  single most bug-prone part of the cutover. Search falls back to a direct
  Firestore read if the local count looks lower than Firestore's live
  `.count()`, in case the full-history backfill hasn't finished yet.
  `firestore_service.dart`'s `sendMessage()` now does `.doc(message.id).set()`
  instead of `.add()`, so the client-generated UUID becomes the actual
  Firestore doc id — required for the optimistic local insert on send to
  share one id with the eventual Firestore doc, no reconciliation needed.
  **Message delivery status** (pending → sent → delivered → read) is fully
  wired: sending inserts a `'pending'` row directly into the local DB (the
  one exception to "writes always go through the Firestore echo"); the sync
  listener flips it to `'sent'` once Firestore's snapshot metadata reports
  `hasPendingWrites == false`; the *recipient's* `LocalSyncService`, the
  first time it sees a new message that isn't its own and has actually
  round-tripped the server, writes back `deliveredAt: serverTimestamp()`
  via the new `FirestoreService.markMessageDelivered()` (mirrors
  `markMessagesRead()`'s pattern, just triggered on receipt instead of on
  chat-screen-open) — the sender's own listener then sees that field and
  shows `'delivered'` (gray double tick); `'read'` is the pre-existing
  `readBy`/`readTimes` logic, unchanged, and takes priority once true.
  Reactions/read-receipt live updates, voice note playback, and image
  rendering were all left untouched — they operate on the same `Message`
  model shape regardless of source.

  **A real production bug was found and fixed during this phase**, worth
  knowing about since the same pattern can recur: `messageFromRow()`
  originally used bare `{}` as the fallback for null `reactions`/
  `readTimes` fields — in Dart, an untyped `{}` map literal defaults to
  `Map<dynamic, dynamic>` at runtime, not `Map<String, dynamic>`, even when
  it visually sits inside a `Map<String, dynamic>` literal. `Message.fromMap()`'s
  `as Map<String, dynamic>?` cast on that then throws, and since the
  original code converted the whole row list via a single `.map().toList()`,
  ONE throwing conversion silently killed the *entire* message list — which
  is nearly every message, since most have no reactions/read receipts.
  Fixed by explicitly typing the fallback (`<String, dynamic>{}`) and by
  converting row-by-row with per-row try/catch + logging (`_applyRows()` in
  chat_screen.dart, mirrored in `TodoDao.watchAllAsModels()`/
  `CommentDao.watchForTodoAsModels()` below) so a single bad row is skipped
  and logged instead of taking the whole screen down. Regression-tested in
  `test/local_sync_merge_test.dart`'s `messageFromRow` group — reproduced
  the exact crash first, then verified the fix.
- ✅ **Phase 3 (todo_screen.dart / sticky_board.dart cutover)**: same
  pattern as Phase 2. `TodoDao.watchAllAsModels()`/`watchByIdAsModel()` and
  `CommentDao.watchForTodoAsModels()` (both in `lib/local_db/daos/`) convert
  row-by-row with per-row try/catch, same lesson as the message bug above.
  `todo_screen.dart`'s four Firestore streams (`todoStream`, `commentStream`
  ×2, `todoDocStream`) all replaced with their local-DB equivalents; writes
  unchanged (still go through `FirestoreService`). `sticky_board.dart`'s two
  `stickyNotesStream()` usages (main board + archive sheet) replaced with
  `StickyNoteDao.watchAll()`, reading typed fields (`note.textContent`,
  `note.isArchived`, etc.) instead of fragile `doc['field']` map access —
  there's no dedicated sticky-note model, so the Drift-generated `StickyNote`
  row class is used directly as the model. `TodoItem.fromMap()` was already
  defensive about the checklist-items-Map-cast pattern (uses
  `Map<String, dynamic>.from(item as Map)`), so it didn't need the same fix
  messages needed. Notification scheduling (`scheduleTodoReminder`,
  `syncTodoNotifications`, `cancelTodoReminder`) untouched and confirmed
  unaffected — `todo.id` and decrypted-title flow are identical to before,
  only the `TodoItem` list's source changed.
- ✅ **Phase 4 (BackupService data-source switch)**: `runBackup()`'s four
  delta fetches (`fetchTodosSince`/`fetchCommentsSince`/`fetchMessagesSince`/
  `fetchStickyNotesSince`) now read `TodoDao`/`CommentDao`/`MessageDao`/
  `StickyNoteDao`'s new `fetchSince()` methods instead of calling
  `FirestoreService` directly — same "where updatedAt > cursor" semantics
  (comments use `createdAt`, unchanged). Each DAO's `fetchSince()` returns
  the exact Firestore-delta shape (`Map<String, dynamic>` with an `'id'`
  key, ISO-8601 string dates) via new `*MapFromRow()` functions in
  `converters.dart` — this is the SAME map shape `Message.fromMap()`/
  `TodoItem.fromMap()`/etc. already consume, so `backup_merge.dart`'s pure
  functions (`mergeDelta`, `sanitizeForJson`, `applyTombstones`,
  `maxTimestampField`) needed **zero changes**, exactly as planned — local
  DB rows store dates as epoch-millis ints, so this conversion step is
  load-bearing, not cosmetic (skipping it would silently break every
  `DateTime.parse()` call downstream). `_verifyIntegrity()` was deliberately
  left untouched, still comparing against live Firestore
  (`countTodos`/`countMessages`/`countStickyNotes`) — it exists specifically
  to catch a broken sync silently under-reporting, so it must never be
  satisfied by the same local copy it's supposed to be checking against.
  New tests: `MessageDao.fetchSince()`'s cursor semantics (null → everything,
  strict-after filtering, correct delta shape) in `test/message_dao_test.dart`.
- ✅ **Post-Phase-4 fix: incremental message backfill.**
  `LocalSyncService._backfillFullMessageHistory()` originally called
  `fetchMessagesSince(coupleId, null)` — unconditionally "everything" — on
  *every single app launch*, not just fresh installs, re-reading the
  entire message history from Firestore every time even though the local
  DB already had it all from last session. Fixed with a new
  `local_sync_cursor_store.dart` (`LocalSyncCursorStore`, SharedPreferences-
  backed, same pattern as `BackupCursorStore` but deliberately a separate
  cursor — this tracks local-DB sync freshness, not Drive backup
  freshness) persisting the newest message `updatedAt` actually backfilled;
  subsequent launches only fetch the delta. New pure helper
  `converters.dart` → `maxRawTimestampField()` computes that cursor from a
  raw (pre-sanitized) Firestore fetch — unlike `backup_merge.dart`'s
  `maxTimestampField()`, which only ever sees already-sanitized ISO
  strings, this handles the mixed `Timestamp`/`String` shape a fresh fetch
  actually has. This directly reduces the Firestore read-count cost
  flagged earlier in the project, on top of the startup-time win.
- ✅ **Phase 5 (fresh-install hydration)**: new
  `lib/services/local_db_hydration_service.dart` —
  `LocalDbHydrationService.hydrateFromBackupAndLiveGap()` calls the existing
  `BackupService.restoreFromBackup(dryRun: false)` unchanged (already merges
  the Drive backup with live Firestore in memory, live wins conflicts), then
  writes the merged `BackupSnapshot`'s four lists into the local DB via
  `messageRowFromFirestoreMap`/`todoRowFromFirestoreMap`/
  `commentRowFromFirestoreMap`/`stickyNoteRowFromFirestoreMap` +
  each DAO's `upsertBatch()` — the exact same converter functions and write
  path `LocalSyncService`'s live listeners already use, so this is a thin
  orchestration layer, not new conversion logic. Row-by-row try/catch (same
  defensive pattern as Phase 2's bug fix) so one malformed archived doc can't
  abort the whole restore; docs missing an `id` (or, for comments, `todoId`)
  are skipped and logged. Never writes back to Firestore — this only makes
  `restoreFromBackup()`'s already-computed result durable somewhere the UI
  reads from, instead of discarding it after seeding the backup cursor.
  `main_shell.dart`'s `_runFullHistoryRestore()` now calls this instead of
  `BackupService` directly; `resetDecryptionState()` call after is unchanged.
  New tests in `test/local_db_hydration_test.dart` (backup-shaped doc list →
  DAO upsert, for all four tables, plus the missing-id-skip behavior).
- ✅ **Post-Phase-5 fix: messages listener was silently deleting real
  messages from the local DB.** Found via device testing: "Inspect Local
  DB" showed a persistent, non-recovering message-count deficit vs. live
  Firestore (e.g. 1130 vs 1132) that a fresh app restart didn't fix.
  Root cause: `LocalSyncService._watchMessages()`'s query is windowed
  (`.orderBy('sentAt', descending: true).limit(50)`) — whenever a new
  message pushes the oldest message out of that top-50 window, Firestore's
  snapshot listener reports a `DocumentChangeType.removed` doc-change for
  it, exactly as if it had been deleted. The listener code didn't
  distinguish "fell out of a windowed query" from "actually deleted," so
  it called `messageDao.deleteById()` on it — silently erasing one real
  message from the local DB every time a new message was sent, forever.
  There is no `deleteMessage()` anywhere in this codebase (messages are
  never actually deletable), so a `removed` event on this listener can
  never legitimately mean a real delete. Fixed by no longer treating
  `removed` as a deletion on the messages listener at all (todos/sticky
  notes/comments listeners are unaffected — their queries have no
  `.limit`, so `removed` there is unambiguous and still correctly means a
  real delete). Since already-affected devices' backfill cursor (Post-
  Phase-4 fix) had already advanced past the erased messages and would
  never re-fetch them, `local_sync_cursor_store.dart`'s key was bumped
  (`_v1` → `_v2`) to force exactly one more full backfill on next launch,
  self-healing any data this bug already erased. Also found and fixed in
  the same pass: two more `FloatingActionButton`s (chat's scroll-to-bottom
  button in `chat_screen.dart`, the snap-send button in
  `widgets/home/quick_snap.dart`) were missing `heroTag: null`, causing
  the same "multiple heroes share the same tag" collision documented under
  Phase 2 to recur — only `todo_screen.dart`'s FAB had been fixed
  previously; these two were missed because the earlier investigation
  assumed (incorrectly) there was only one `FloatingActionButton` in the
  app.

**E2EE posture — do not change:** the local DB stores ciphertext exactly
like Firestore does today. No plaintext at rest locally. Decryption stays
lazy, in-memory, cached per-screen-instance — identical to the existing
`_decryptedTextCache` pattern in `chat_screen.dart`/`todo_screen.dart`, just
fed by Drift rows instead of Firestore docs.

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

Three channels currently used:

| Channel | Type | Direction | What it does |
|---------|------|-----------|--------------|
| `com.theawesomeray.tether/music` | MethodChannel | Native → Flutter | Native pushes via `invokeMethod('onMusicChanged', ...)` map `{track, artist, isPlaying}` when system MediaSession changes. Bidirectional channel used one-way — not an EventChannel |
| `com.theawesomeray.tether/battery` | MethodChannel | Flutter → Native | Flutter calls `invokeMethod('getBatteryInfo')`, gets back `{batteryLevel: Int, isCharging: Bool}` |
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
