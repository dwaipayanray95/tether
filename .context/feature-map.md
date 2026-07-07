# Feature Map

Use this map to identify which files to read or modify when editing specific app features:

### 💬 Chat & Messages
- **Message Bubble Appearance:** `chat_screen.dart` → `_MessageBubble` widget (bottom of file).
- **Timestamp Formatting:** `chat_screen.dart` → `_formatTimestamp()`.
- **Pagination Configuration:** `chat_screen.dart` → `_loadInitialMessages()`, `_loadMore()`.
- **Reply to Message Behaviour:** `chat_screen.dart` → `_replyTo` state + `_buildInput()`.
- **Message Scroll & Highlight:** `chat_screen.dart` → `scrollToMessageById()`.
- **Emoji Reactions:** `chat_screen.dart` → `_ReactionPicker`, `_MessageBubble.onReaction`.
- **Unread Badge Counts:** `firestore_service.dart` → `unreadCountStream()`, `markMessagesRead()`.
- **Message Search Overlays:** `search_screen.dart` + `firestore_service.dart` → `getAllMessages()`.
- **Image Sending Flows:** `chat_screen.dart` → `_pickAndSendImage()`.
- **Firestore Messaging Reads/Writes:** `firestore_service.dart` → `messageStream()`, `sendMessage()`, `fetchMessagePage()`.
- **E2EE Voice Notes & Scrubbing:** `chat_screen.dart` → `VoicePlaybackWidget` + `voice_service.dart` (recording via record, play/decode via flutter_sound).
- **Date Breaker Banners:** `chat_screen.dart` → `buildDateHeader()`.
- **E2EE Pre-cache Scroll Optimization:** `chat_screen.dart` → `_initSharedKey()` / caching `_sharedKey` state.

### 🏠 Home Screen & Presence
`home_screen.dart` was refactored down to 252 lines (header + sticky-board header
only) — everything below is its own widget file under `lib/widgets/home/`.
- **Header / online presence / last seen:** `home_screen.dart` header + `firestore_service.dart` → `presenceStream()`.
- **Compass / distance / proximity radar:** `widgets/home/compass_card.dart`.
- **Poke Interactions:** `widgets/home/poke_card.dart` + `firestore_service.dart` → `sendPoke()`.
- **Sticky Notes Board:** `widgets/home/sticky_board.dart`.
- **Music Card:** `widgets/home/music_card.dart`.
- **Quick Action Layout:** `widgets/home/quick_actions.dart`.
- **Quick Snap card / Polaroid viewer:** `widgets/home/quick_snap.dart` → `gallery_screen.dart`.
- **Profile completion bar:** `widgets/home/profile_completion_bar.dart` → `partner_info_screen.dart`.

### 👤 Partner Info & Snaps
- **Profile fields:** `partner_info_screen.dart` + `partner_profile_model.dart` (`PartnerProfile`) — birthday/zodiac, clothing sizes map, shoe/ring size, allergies, food dislikes, favorite foods, favorite color, top-5 favorite movies.
- **Anniversary (shared field):** `partner_info_screen.dart` + `firestore_service.dart` → `updateAnniversary()`.
- **Snap send / local storage / Drive backup:** `widgets/home/quick_snap.dart` + `local_storage_service.dart` (saves under `getApplicationDocumentsDirectory()/snaps/`, uploads PNG to Drive via `GoogleDriveService`).
- **Full gallery / delete:** `gallery_screen.dart`.

### 🔔 Notifications & FCM
- **Outbound FCM Calls:** `fcm_service.dart` → `send()` (HTTP v1 payload styling with service account key).
- **FCM Service Credentials:** `config/notification_config.dart`.
- **Foreground Handlers:** `notification_service.dart` → `FirebaseMessaging.onMessage`.
- **Background Handlers:** `notification_service.dart` → `firebaseMessagingBackgroundHandler`.
- **Native platform channels:** `MainActivity.kt` — `com.theawesomeray.tether/music` (MethodChannel, native push), `.../battery` (MethodChannel, Flutter-requested), `.../compass` (EventChannel, native stream), `.../shortcuts` (MethodChannel, Flutter-requested — see below). Music is *not* an EventChannel despite the name.
- **Conversation-priority notifications (WhatsApp/Instagram-style top-of-shade grouping):** two parts, both required:
  1. `importance`/`priority: max` alone does NOT get a notification into Android 11+'s "Conversations" section — that requires a matching long-lived dynamic shortcut published via `ShortcutManagerCompat`. `notification_service.dart` → `_pushConversationShortcut()` calls the native `.../shortcuts` channel on every `initialize()` (safe to call repeatedly); `MainActivity.kt` → `pushConversationShortcut()` does the `ShortcutInfoCompat`/`Person` publish. `_showLocal()` sets `shortcutId` + `MessagingStyleInformation` + `AndroidNotificationCategory.message` for `chat`/`poke`/`snap`/`todo` types (all "from the partner" in this 2-person app).
  2. **All four of those FCM types must be data-only** (`fcm_service.dart` → `isDataOnly`). If FCM's own `notification` block were sent instead, Android auto-displays a plain system notification whenever the app is backgrounded/killed — which is the common case — completely bypassing `_showLocal()` and therefore the shortcut/style/category above. `firebaseMessagingBackgroundHandler` (in `notification_service.dart`) now explicitly re-initializes `FlutterLocalNotificationsPlugin` (fresh isolate) and calls `_showLocal()` itself for these types instead of relying on the OS default. The foreground `onMessage` listener reads `title`/`body` from `message.data` (not `message.notification`, which is null for data-only messages).

### 🔄 Auto-Update & Diagnostics
- **Release check:** `update_service.dart` → `checkForUpdate()`.
- **Release dialogues:** `widgets/update_dialog.dart` (re-route UI alerts for updating APKs).
- **Logging logic:** `settings_screen.dart` + `log_service.dart` + `diagnostics_screen.dart`.

### 💾 Backup (unified pipeline — see `.context/database-schemas.md` for schema)
- **User-facing screen:** `backup_screen.dart` — "Backup Now" button, progress bar, last backup date/size. Linked from `settings_screen.dart` ("Backup" tile).
- **Orchestration:** `backup_service.dart` → `runBackup()` (incremental: fetch deltas since cursor, merge into existing Drive backup, encrypt, upload, verify, rotate, promote), `restoreFromBackup()` (download + decrypt + merge with live Firestore; `dryRun: true` for preview-only), `inspect()` (read-only diagnostics).
- **Pure/testable logic (no network):** `backup_merge.dart` → `mergeDelta()`, `applyTombstones()`, `sanitizeForJson()`, `maxTimestampField()`, `computeRotationPlan()`. Covered by `test/backup_merge_test.dart` — extend this file, not integration tests, when changing merge/rotation logic.
- **Local cursor (per-collection "synced up to" timestamps + last backup size/time):** `backup_cursor_model.dart` + `backup_cursor_store.dart` (SharedPreferences-backed, per-device).
- **Drive file naming / rotation contract:** `backup_config.dart` (`BackupConfig`) — also holds `backedUpPreferenceKeys`, the allowlist of SharedPreferences keys included in backups.
- **Snapshot content shape:** `backup_snapshot_model.dart` (`BackupSnapshot`) — todos, comments, messages, stickyNotes, profiles, coupleDoc, preferences.
- **Trigger cadence:** `foreground_backup_scheduler.dart` → `ForegroundBackupScheduler.runIfDue()` — called from `main_shell.dart` on cold start and every `AppLifecycleState.resumed`; runs at most once per 24h (persisted via the cursor), matching the same "check on open, run if due" pattern as `_checkForUpdate()`.
- **Generic Drive file helpers (find/upload/download/rename/delete by name):** `google_drive_service.dart` → `findFileIdByName()`, `uploadOrReplaceBytes()`, `downloadBytesByName()`, `renameFileByName()`, `deleteFileByName()`.
- **Access token caching:** `google_drive_service.dart` → `_getAccessToken()` caches the token for 50 min (TTL, not an authoritative expiry — the plugin doesn't surface one) so `authorizationForScopes()` isn't hit on every Drive call; a 401 interceptor evicts the cache early so the next call self-heals instead of waiting out the full TTL.
- **Deletion tombstones (so cursor-based delta queries can catch removals):** `firestore_service.dart` → `_recordDeletion()`, `deletionsSince()`, `pruneDeletionsBefore()`.
- **Dev-only manual test harness (will be dropped once the feature is stable):** `diagnostics_screen.dart` → "Run Backup Now", "Inspect Backup State", "Restore Preview", "Run Backup If Due".
- **E2EE key backup is separate, not part of this pipeline:** `main_shell.dart` → `_checkE2EESetup()` + `crypto_service.dart` + `google_drive_service.dart` → `backupKeyBackup()`/`restoreKeyBackup()` (still writes `tether_key_backup.json` directly). Only ever runs once per install now (persisted `e2ee_backup_verified` flag), not on every app open.
