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

### 3. Location Screen Dead Code
- **Removed Screens:** `lib/screens/location_screen.dart` (the entire Google Maps full-screen view showing both partners' pins).
- **Details:** The app has removed this screen since location streaming and map view features are handled elsewhere or unused, keeping the codebase completely clean from dead references.

### 4. WorkManager-based background backup scheduling
- **Removed files:** `lib/services/background_backup_task.dart`, `lib/services/background_run_log.dart`. Removed the `workmanager` package dependency entirely.
- **Why:** Every Drive operation in the backup pipeline needs a Google Sign-In access token via `attemptLightweightAuthentication()`, which requires a foreground Activity context on Android. When actually triggered via a real WorkManager one-off task (verified through a "Trigger Background Task Now" diagnostic button before removal), Firestore reads and crypto succeeded in the background isolate every time, but the *first* Drive call failed every time with `Exception: Google Sign-In user is not available.` — even after calling `GoogleSignIn.instance.initialize()` in the background isolate. This is a hard platform constraint, not a bug that can be patched around.
- **Replaced by:** `lib/services/foreground_backup_scheduler.dart` (`ForegroundBackupScheduler.runIfDue()`) — checked on app open/resume, runs at most once per 24h, using the same "check on open, run if due" pattern as the update-checker. **Do not reintroduce WorkManager (or any headless-isolate scheduler) for Drive-touching work.**

### 5. Proactive/periodic Google Sign-In scope validation
- **Removed:** `MainShell._validateGoogleScopes()` and its daily-throttled variant. Previously ran on every cold start (later throttled to once/24h) to detect if `GoogleScopes.all` had grown beyond what the signed-in user had granted, signing them out if so.
- **Why:** `attemptLightweightAuthentication()` briefly flashes Android's Credential Manager UI (AssistedSignInActivity/CredentialChooserActivity) even for a purely silent/cached lookup. Running this proactively on a schedule — regardless of whether the user was about to use a Drive feature — was a direct, avoidable cause of a visible "quick sign-in" flash on every app open.
- **Replaced by:** Lazy/reactive checking in `GoogleDriveService._getAccessToken()` — if a Drive call's cached authorization is missing a scope, it signs the user out right there, so the *next* login naturally re-requests the full current scope set. Only fires if a Drive feature is actually used without the needed scope, not on a schedule.

### 6. Ad-hoc, unencrypted preferences backup
- **Removed:** `GoogleDriveService.backupPreferences()` / `restorePreferences()` (wrote/read a plain, unencrypted `tether_preferences.json` on Drive). Removed `MainShell._backupPrefsToCloud()` (ran on every app background/inactive transition) and `_restorePrefsFromCloud()` (ran on every cold start, later throttled to 24h).
- **Why:** Preferences backup was a separate, ad-hoc system from the rest of the backup pipeline — different cadence, different Drive file, no encryption, and (before the fix) it was dumping *every* SharedPreferences key including this app's own internal bookkeeping (the backup cursor, the E2EE-verified flag, cached location fixes) — restoring those onto a different device or after a fresh install would have caused real bugs.
- **Replaced by:** Preferences are now one field (`preferences`) in the same encrypted `BackupSnapshot` that `BackupService` already produces for everything else — see `.context/feature-map.md` → Backup section. Only the explicit allowlist `BackupConfig.backedUpPreferenceKeys` is ever included (currently just `logging_enabled`). **Never add a key to that allowlist that isn't a genuine user-facing setting.**

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
