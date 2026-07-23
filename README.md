# Tether

A private, end-to-end encrypted app built for two people — chat, shared to-dos, sticky notes, photo "snaps," presence, and a couple's shared memory, backed by a local-first on-device database with encrypted, dual-destination backups.

Tether is not a general-purpose product (yet) — it's a real app currently deployed for one couple, built to eventually support onboarding new couples. See [Architecture](#architecture) and [Roadmap](#roadmap) for what that would take.

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
  - [Local-first data flow](#local-first-data-flow)
  - [End-to-end encryption](#end-to-end-encryption)
  - [Backup pipeline](#backup-pipeline)
  - [Notifications](#notifications)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Firebase Setup](#firebase-setup)
  - [Required Config Files](#required-config-files)
  - [Running Locally](#running-locally)
- [Optional: Headless Background Sync](#optional-headless-background-sync)
- [CI / Release Builds](#ci--release-builds)
- [Security Notes](#security-notes)
- [Roadmap](#roadmap)
- [License](#license)

---

## Features

- **Chat** — end-to-end encrypted text, images, and voice notes; replies, emoji reactions, full-history local search, and message delivery status (pending → sent → delivered → read).
- **Shared to-dos** — tasks with due dates, priority, checklists, assignment, and threaded comments.
- **Sticky notes** — a shared corkboard for quick notes.
- **Snaps** — Polaroid-style photo sharing with a local + cloud-synced gallery.
- **Presence** — online/last-seen status, live battery level, and music-listening status.
- **Backups** — encrypted, incremental backups to Google Drive *and* to a persistent on-device folder (survives app uninstall/reinstall), with automatic freshness comparison between the two on restore.
- **Diagnostics** — an in-app screen for inspecting sync/backup state and app logs, useful when debugging without a debugger attached.

## Architecture

### Local-first data flow

The UI never reads Firestore directly. Instead:

```
Firestore (rolling live relay — real-time delivery between the two devices)
    │  live snapshot listeners
    ▼
Local on-device database (Drift/SQLite) ← single source of truth for the UI
    ▲
    │  one-time hydration on fresh install
Google Drive backup / local backup folder (permanent full-history archive)
```

- **Writes** go straight to Firestore for real-time delivery to the partner's device; the local DB is updated by the same live listener that would show the partner's own writes (no separate write path, avoiding an entire class of dual-write bugs) — except for outgoing messages, which get an optimistic local insert immediately on send (for offline-friendly, immediate UI feedback), reconciled once the write round-trips.
- **Firestore is a rolling relay, not an archive.** It's the live delivery layer between the two devices; it is *never* written back to with recovered/historical data. The backup is the permanent record.
- **On a fresh install**, the encrypted backup (from Drive, or the local folder if Drive is unavailable) is merged with whatever's currently live in Firestore and hydrated into the local database, so a new device ends up with full history — including anything Firestore itself may have already purged.

### End-to-end encryption

- Key exchange: **X25519** (ECDH) between the two partners' devices.
- Message/content encryption: **AES-GCM**.
- The local on-device database stores ciphertext only — no plaintext at rest, matching Firestore's own posture. Decryption happens client-side and is cached in memory (bounded, not unbounded) for the current session.
- The private key itself is additionally backed up to Drive, encrypted with a **PIN-derived key** (PBKDF2-HMAC-SHA256, 600,000 iterations) — this is what lets a fresh install recover E2EE access without needing the original device.

### Backup pipeline

One unified, incremental pipeline (`BackupService.runBackup()`) handles messages, to-dos, comments, sticky notes, profiles, the couple document, an allowlisted set of app preferences, and photo snaps — all synced together in one cycle, not as separate ad-hoc Drive calls.

- **Dual destination:** every run writes to an auto-created `Documents/Tether` folder on-device (via Android's MediaStore — survives app uninstall, unlike normal app storage, and needs no folder-picker) *before* attempting Google Drive, so a full/offline Drive never costs you a backup.
- **Safety model:** a new backup is written to a "pending" file, integrity-checked against live Firestore record counts, and only then promoted over the last known-good backup — nothing is ever overwritten speculatively.
- **Restore freshness:** on restore, both the Drive copy and the local-folder copy are checked, and whichever is actually newer (compared via the backup's own embedded generation timestamp) is used — not just "Drive if reachable."
- **Cadence:** checked on every app open/resume, runs at most once every 24 hours per device. See [Optional: Headless Background Sync](#optional-headless-background-sync) for extending this to run without the app being open.

### Notifications

Push notifications (chat, pokes, snaps, to-do updates) are sent via FCM's HTTP v1 API and rendered as native Android "Conversations" (the same grouping WhatsApp/Instagram use) via a matching dynamic shortcut — this requires all four notification types to be sent as data-only FCM payloads, rendered entirely client-side, since Android's own default notification-from-`notification`-payload path bypasses that grouping.

## Tech Stack

| Layer | Choice |
|---|---|
| Client | Flutter (Android; iOS scaffolding present but Android is the maintained target) |
| Local database | [Drift](https://drift.simonbinder.eu/) (SQLite) |
| Backend | Firebase — Firestore, FCM, Cloud Functions |
| Auth | Google Sign-In (`google_sign_in` v7, Credential Manager-based) |
| Encryption | `cryptography` package — X25519 + AES-GCM |
| Local persistent backup | Android MediaStore (native Kotlin platform channel) |
| Push | Firebase Cloud Messaging (HTTP v1, service-account JWT auth) |

## Project Structure

```
lib/
├── config/          # Gitignored secrets (env_config.dart, notification_config.dart) + scope/backup config
├── models/          # Plain data classes (Message, TodoItem, PartnerProfile, BackupSnapshot, ...)
├── local_db/        # Drift schema: tables, DAOs, and Firestore-doc ↔ row converters
├── screens/         # Top-level screens (chat, todo, home, backup, diagnostics, settings, ...)
├── widgets/home/    # Home-tab widgets (sticky board, poke card, quick snap, music card, ...)
├── services/        # All business logic — Firestore/Drive/FCM/crypto/backup/local-sync services
└── theme/           # App-wide styling

functions/           # Firebase Cloud Functions (TypeScript) — see below
test/                # Unit tests (Drift DAOs, backup merge logic, hydration)
.context/            # Extended internal architecture docs (see AGENTS.md)
```

For a deeper reference (file-by-file feature map, database schemas, hard rules for AI-assisted development), see [AGENTS.md](AGENTS.md) and `.context/`.

## Getting Started

### Prerequisites

- Flutter SDK (see `environment.sdk` in `pubspec.yaml` for the exact constraint)
- A Firebase project (Firestore and FCM enabled)
- Android Studio / an Android SDK for building and running

### Firebase Setup

1. Create a Firebase project and add an Android app with package name `com.theawesomeray.tether` (or update `applicationId` in `android/app/build.gradle.kts` to your own).
2. Download `google-services.json` into `android/app/` (gitignored — see `android/app/google-services.json.example` for the expected shape).
3. Deploy the included security rules and indexes:
   ```
   firebase deploy --only firestore:rules,firestore:indexes,storage
   ```
4. Enable Google Sign-In in Firebase Authentication, with the Drive scopes (`drive.file`, `drive.appdata`) configured — see `lib/config/google_scopes.dart`.

### Required Config Files

Two files are gitignored and must be created locally (or restored via CI secrets — see [CI / Release Builds](#ci--release-builds)):

**`lib/config/env_config.dart`**
```dart
class EnvConfig {
  static const allowedEmails = [
    'partner1@example.com',
    'partner2@example.com',
  ];
  static const coupleId = 'your-couple-id';
  static const googleWebServerClientId = ''; // see Optional: Headless Background Sync
}
```

**`lib/config/notification_config.dart`** (a Firebase service account key, for FCM's HTTP v1 API)
```dart
class NotificationConfig {
  static const projectId = 'your-firebase-project-id';
  static const clientEmail = 'your-service-account@your-project.iam.gserviceaccount.com';
  static const privateKey = '-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n';
}
```

You'll also need a Google Maps API key injected via the `MAPS_API_KEY` environment variable at build time (see `android/app/build.gradle.kts`), and a release keystore if building a signed release APK.

### Running Locally

```
flutter pub get
flutter run
```

Run the test suite with:

```
flutter test
```

## Optional: Headless Background Sync

By default, backups only run while the app is open/resumed — Google Sign-In's silent re-authentication doesn't work from a headless background context on Android. An optional path exists to enable true background sync (and, as a side effect, eliminates the occasional Google Sign-In UI flash on app launch), at the cost of a small amount of backend infrastructure:

1. A Cloud Function pair (`functions/`) exchanges a one-time Google `serverAuthCode` for an OAuth refresh token, then mints fresh Drive access tokens from it on demand — both steps require a "Web application" OAuth client secret, which cannot safely live on-device, hence the small server component.
2. Requires the Firebase project to be on the **Blaze (pay-as-you-go)** plan (Cloud Functions aren't available on the free tier) — realistic cost for personal use is $0/month against the free invocation tier, but a billing account is required.
3. Setup:
   ```
   cd functions
   npm install
   firebase functions:secrets:set GOOGLE_WEB_CLIENT_ID
   firebase functions:secrets:set GOOGLE_WEB_CLIENT_SECRET
   firebase functions:secrets:set ALLOWED_EMAILS
   firebase deploy --only functions
   ```
4. Fill in `EnvConfig.googleWebServerClientId` with the Web OAuth client ID (Firebase auto-creates one alongside your Android client — reuse it rather than creating a new one).

See `functions/src/index.ts` for the full explanation and setup notes. Left unconfigured, this is a complete no-op — the app functions normally without it.

## CI / Release Builds

`.github/workflows/build-apk.yml` has a `quality-gate` job (static analysis, tests, dependency license check, secret scan) that must pass before the `build` job runs. `build` restores the gitignored config files above from GitHub Actions secrets — `ENV_CONFIG_DART`, `NOTIFICATION_CONFIG_DART`, `GOOGLE_SERVICES_JSON` (raw file contents) — along with the signing keystore (`KEYSTORE_BASE64`, `KEY_PROPERTIES`). `ENV_CONFIG_DART`/`NOTIFICATION_CONFIG_DART` fall back to dummy placeholder values if unset so ad-hoc/forked runs still type-check without exposing real secrets; `GOOGLE_SERVICES_JSON` has no such fallback since the Android build can't proceed without it at all.

## Security Notes

- All chat/comment content is end-to-end encrypted; Firestore, the local database, and both backup destinations only ever store ciphertext.
- Firestore security rules restrict all reads/writes to an explicit allowlist of two account emails (see `firestore.rules`) — this app is not currently open to arbitrary signups (see [Roadmap](#roadmap)).
- No secrets, API keys, or personal information are committed to this repository — everything sensitive is injected at build/deploy time via gitignored config files or CI secrets.
- Found a security issue? Please report it privately rather than opening a public issue.

## Roadmap

- **Multi-couple onboarding.** The app is currently architected as one deployment per couple (a fixed 2-email allowlist, a single hardcoded couple ID). Turning this into a real multi-tenant app — open signup, an invite/pairing flow, and dynamic per-couple data isolation — is a planned but not-yet-started rework of the identity and security-rules layer.
- **Headless background sync**, made default rather than opt-in, once the multi-tenant backend exists to support it more cheaply at scale.
- A scheduled Firestore purge job for messages older than 90 days (the backup pipeline already assumes this will eventually exist and handles it gracefully — Firestore isn't the archive, the backups are).

## License

All rights reserved — see [LICENSE](LICENSE). This is not currently an open-source project; the repository is public for portfolio/reference purposes only.
