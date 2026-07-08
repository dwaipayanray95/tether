# Project Structure

Tether is built using Flutter (Dart) and standard Android Native configuration. Calling and proximity features have been completely removed. `location_screen.dart` was also removed (see removed-features.md #3) — do not reference it.

```text
lib/
├── main.dart                    # App entry point: Firebase init, GoogleSignIn.initialize(), auth gate
├── config/
│   ├── notification_config.dart # FCM service account credentials (private)
│   ├── env_config.dart          # Gitignored: allowedEmails, coupleId (restored via ENV_CONFIG_DART secret)
│   ├── google_scopes.dart       # GoogleScopes.basic (email, profile) / .drive (drive.file, drive.appdata) / .all
│   └── backup_config.dart       # BackupConfig — Drive file naming/rotation contract + backedUpPreferenceKeys allowlist
├── models/
│   ├── message_model.dart       # Message (id, senderId, text, type, imageUrl?, audioUrl?, duration?, sentAt,
│   │                            #   updatedAt, readBy, readTimes, reactions, replyTo*). MessageType: text|image|poke|voice
│   ├── todo_model.dart          # TodoItem (id, title, isDone, createdBy, createdAt, updatedAt, ...), ChecklistItem
│   ├── comment_model.dart       # TodoComment — stored as a SUBCOLLECTION at todos/{todoId}/comments/{id}, not inline
│   ├── user_model.dart          # Basic user data
│   ├── partner_profile_model.dart    # PartnerProfile — birthday, clothingSizes{}, shoeSize?, ringSize?, allergies[],
│   │                            #   foodDislikes[], favoriteFoods[], favoriteColor?, favoriteMovies[] (max 5)
│   ├── backup_cursor_model.dart      # BackupCursor — per-collection "synced up to" timestamps + last backup size/time
│   ├── backup_snapshot_model.dart    # BackupSnapshot — decrypted backup file content (todos, comments, messages, stickyNotes, profiles, coupleDoc, preferences)
│   └── deletion_record_model.dart    # DeletionRecord — one tombstone (collection, docId, deletedAt)
├── screens/
│   ├── main_shell.dart          # Root scaffold: bottom nav, update check, handles pending notification, ForegroundBackupScheduler.runIfDue()
│   ├── home_screen.dart         # Home tab — now only 252 lines (header + sticky-board header); everything else
│   │                            #   lives in widgets/home/* below. Do not look for _buildCompassCard() etc. here.
│   ├── chat_screen.dart         # Chat tab: paginated messages, search, reply, reactions, voice notes
│   ├── search_screen.dart       # Full-history message search overlay
│   ├── todo_screen.dart         # Shared to-do list and comments
│   ├── login_screen.dart        # Google Sign-In gate
│   ├── partner_info_screen.dart # Tabbed "Me"/partner profile screen — see PartnerProfile model above
│   ├── gallery_screen.dart      # Full gallery of saved Snaps (local + Drive backup), delete with confirmation
│   ├── settings_screen.dart     # App version (dynamic), sign out, diagnostics link, Backup tile
│   ├── diagnostics_screen.dart  # Log viewer + dev-only backup test harness (dropped once backup is stable)
│   └── backup_screen.dart       # User-facing Backup screen: "Backup Now", progress bar, last backup date/size
├── services/
│   ├── auth_service.dart        # Firebase Auth + Google Sign-In; isRay, myName, partnerName, getGoogleUser() (cached)
│   ├── crypto_service.dart      # E2EE keypair gen/exchange + AES-GCM; getSharedKey() caches + in-flight-guards derivation
│   ├── voice_service.dart       # Encrypts Opus recording (record) / decrypts for playback (flutter_sound)
│   ├── firestore_service.dart   # All Firestore reads/writes (messages, todos, comments subcollection, presence,
│   │                            #   poke, sticky notes, deletion tombstones, backup delta-fetch/count queries)
│   ├── fcm_service.dart         # Sends FCM via HTTP v1 API with service-account JWT
│   ├── notification_service.dart# FCM receive handling (foreground/background) & local notifications
│   ├── location_service.dart    # Geolocator + Firestore location upload/stream
│   ├── local_storage_service.dart # On-device Snap storage (getApplicationDocumentsDirectory()/snaps/); uploads
│   │                            #   Polaroid PNGs to Drive backup via GoogleDriveService after local save
│   ├── music_sync_service.dart  # Native MediaSession bridge — now-playing track sync
│   ├── update_service.dart      # GitHub Releases API check + APK download & install
│   ├── log_service.dart         # File-based debug logging (toggled in Settings/Diagnostics)
│   ├── nav_service.dart         # Global navigatorKey for navigation from outside widget tree
│   ├── google_drive_service.dart    # Drive REST calls: snap/key-backup uploads + generic named-file helpers
│   │                            #   (find/upload/download/rename/delete by name) used by BackupService
│   ├── backup_service.dart          # BackupService — runBackup()/restoreFromBackup()/inspect(), the unified backup pipeline
│   ├── backup_merge.dart            # Pure merge/rotation logic, unit-tested in test/backup_merge_test.dart
│   ├── backup_cursor_store.dart     # SharedPreferences-backed persistence for BackupCursor
│   └── foreground_backup_scheduler.dart # ForegroundBackupScheduler.runIfDue() — 24h-throttled trigger called from main_shell
├── local_db/                    # Local-first on-device DB (drift/SQLite) — see AGENTS.md "Local-First Architecture"
│   ├── app_database.dart           # AppDatabase — opens tether_local.sqlite, ties tables together
│   ├── app_database.g.dart         # Generated by build_runner — do not hand-edit
│   └── tables/                     # Messages/Todos/TodoComments/StickyNotes — mirror each model's toMap()/fromMap()
├── theme/
│   └── app_theme.dart           # Colours, typography, component themes (coral #E8715A palette)
└── widgets/
    ├── home/                    # home_screen.dart composes these — edit here, not home_screen.dart, for these features
    │   ├── compass_card.dart        # Bearing/distance to partner, proximity radar, heart-pulse animation
    │   ├── music_card.dart          # Partner's now-playing track + vinyl rotation animation
    │   ├── poke_card.dart           # "Poke" mechanic — cooldown + haptic feedback
    │   ├── sticky_board.dart        # Pastel sticky notes board: add/archive/restore/delete + archive sheet
    │   ├── quick_snap.dart          # Last received Snap card — E2EE decrypt, full-screen Polaroid viewer
    │   ├── quick_actions.dart       # Quick-access row: To-do, unread Chat count, Partner Info
    │   └── profile_completion_bar.dart # Slim progress bar for the 9 PartnerProfile fields, hides at 9/9
    └── update_dialog.dart       # Two-dialog update flow: release notes → download progress
```

```text
android/
└── app/src/main/kotlin/com/theawesomeray/tether/
    └── MainActivity.kt          # 3 channels: music (MethodChannel, native push), battery (MethodChannel,
                                 #   Flutter-requested), compass (EventChannel, native stream) — see AGENTS.md
```
