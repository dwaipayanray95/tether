# Key Constants & Configurations

These are the core hardcoded constants, credentials, helper guidelines, styling colors, and routing schemas used in Tether.

## Core Constants & Secrets

- **Configuration File:** All secret parameters are stored inside `lib/config/env_config.dart` (which is gitignored and populated on GitHub Actions runners using `ENV_CONFIG_DART`).
- **Couple Identifier:** `EnvConfig.coupleId` (`'ray-aproo'`) — shared ID for Firestore collections.
- **Authorized Emails:** `EnvConfig.allowedEmails` (`['ray@redacted.invalid', 'aproo@redacted.invalid']`).

## End-to-End Encryption (E2EE)

- **Mandatory Architecture Rule:** Every new feature added to the app MUST be end-to-end encrypted. No user-generated content may be stored in plaintext.
- **Cryptography:** AES-GCM (256-bit) and X25519 Elliptic Curve Diffie-Hellman (ECDH) key exchange.
- **Keys Storage:** Private keys are saved locally in Secure Storage (`flutter_secure_storage`). Public keys are published to `/couples/ray-aproo/status/presence` doc under `${userKey}.publicKey`.
- **Key Recovery:** Encrypted locally using a PBKDF2 derived key from the user's 4-digit PIN, and uploaded to Google Drive as `tether_key_backup.json`.
- **Encrypted Payloads:** Messages, Snaps, Tasks, Comments, and Sticky Notes text are stored as base64 JSON objects beginning with `{"ciphertext":` if encrypted.

## Auth & Name Mapping

- `AuthService().isRay` - returns `true` if current user is Ray.
- `AuthService().myName` - returns `'Ray'` or `'Aproo'` (first letter capitalized).
- `AuthService().partnerName` - returns opposite of myName.
- **Lowercase keys:** Use lowercase `'ray'` / `'aproo'` when targeting presence documents, FCM tokens.

## Backup System

- **Config:** `lib/config/backup_config.dart` (`BackupConfig`).
- **Drive folder:** `Tether/` — files: `latest_backup.json.enc` (current), `backup_gen1/2/3.json.enc` (rotated prior generations, oldest deleted once a 4th would be created — `maxBackupGenerations = 3`).
- **`tether_key_backup.json`** is separate — the E2EE private key backup (PIN-encrypted), unrelated to the general backup pipeline.
- **Cadence:** at most once per 24h, checked on app open/resume via `ForegroundBackupScheduler.runIfDue()` — never on a background scheduler (see hard-rules.md).
- **Preferences allowlist:** `BackupConfig.backedUpPreferenceKeys` — only these SharedPreferences keys are ever included in a backup. Currently: `logging_enabled`. Never add an internal bookkeeping key (backup cursor, E2EE-verified flag, cached location) to this list.

## Notification Channels

- `tether_updates_v1` - Default notification channel for messages, pokes, and todo updates.
- Note: The high-importance call channel `tether_calls_v1` has been fully removed.

## Color Palette & Typography (`app_theme.dart`)

```dart
AppTheme.primary       // #E8715A  Warm Coral — Primary action buttons, active icons, accents
AppTheme.primaryLight  // #FFF0EE  Light Coral — Backdrops for tinted action tiles
AppTheme.secondary     // #B5838D  Muted Rose
AppTheme.background    // #FAF8F6  Warm Off-White Scaffold
AppTheme.surface       // #FFFFFF  Cards, Chat Bubbles, Sheet containers
AppTheme.textDark      // #2D2D2D  Main headings, body copy
AppTheme.textMuted     // #9E9E9E  Subtitles, minor details
AppTheme.divider       // #F0EDED  Subtle lines
```

- **Body Typography:** DM Sans
- **Headings & Hero Copy:** Playfair Display

## FCM Send Rules & Targets

- **Primary Handler:** Always send push alerts using `FcmService.send()`.
- **Ignore / Disabled Payloads:** Payloads targeting types `'call_ping'` or `'call_ended'` are ignored by client handlers.
- **Partner target resolution:** `AuthService().partnerName.toLowerCase()` targets `'ray'` or `'aproo'`.
