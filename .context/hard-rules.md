# Hard Rules

These are the critical rules that must always be followed without exception when working on Tether.

| Rule | Detail |
|------|--------|
| **Never push to GitHub** | Do not run `git push`, `git tag`, or `gh release create` unless the user explicitly asks in that message |
| **Never bump `pubspec.yaml`** | The user will manually bump version codes henceforth. Do not auto-increment version code. |
| **Never change `coupleId`** | It is always `'ray-aproo'` — loaded from the gitignored `lib/config/env_config.dart` file. |
| **Never change allowed emails** | Two real personal Gmail addresses — loaded from the gitignored `lib/config/env_config.dart` (`EnvConfig.allowedEmails[0]` = Ray, `[1]` = Aproo). Never write the literal addresses anywhere else. |
| **Never hardcode API keys, secrets, or personal emails in source** | This repo is public. Any real key/credential/email committed to a tracked file is permanently visible in git history even after later removal. All secrets are injected at CI build time via GitHub Actions secrets — see `.github/workflows/build-apk.yml`. |
| **Name comparison is case-sensitive** | `fromName == 'Ray'` (capital R). Partner key strings are lowercase `'ray'` / `'aproo'` |
| **Always run `flutter analyze` before committing** | Fix all errors and warnings first |
| **All backup logic goes through `BackupService`** | Never add a new ad-hoc `GoogleDriveService` call for backing up/restoring app data. Messages, todos, comments, sticky notes, profiles, the couple doc, and the allowlisted app preferences are all backed up together as one encrypted `BackupSnapshot` via `backup_service.dart`. See `.context/database-schemas.md` for the `deletions` tombstone collection and cursor model this depends on. |
| **Never run Google Sign-In calls from a background isolate** | `attemptLightweightAuthentication()` / any Drive call requires a foreground Activity context on Android — confirmed broken when tried via WorkManager (always fails with "Google Sign-In user is not available", even after `GoogleSignIn.instance.initialize()`). All Drive-touching backup logic must run in the foreground (app open/resume), via `ForegroundBackupScheduler`, not a background scheduler. |
| **Never add a proactive/periodic Google scope-check** | Scope validation is lazy/reactive only — `GoogleDriveService._getAccessToken()` signs the user out if a Drive call's cached scope is missing, forcing re-consent on next login. Do not add back a periodic "verify scopes" check on app open — it was removed because it caused Android's Credential Manager UI to visibly flash on every launch. |
| **New `collectionGroup()` queries need a top-level Firestore rule + index** | A nested `match /couples/{coupleId}/{document=**}` rule does *not* authorize a `collectionGroup()` query — Firestore requires a separate top-level rule scoped to that exact collection ID (see `firestore.rules` → the `match /{path=**}/comments/{commentId}` block, added for `fetchCommentsSince()`). It also needs a single-field index **override** with `queryScope: COLLECTION_GROUP` in `firestore.indexes.json` (a composite index entry is rejected — Firestore says "this index is not necessary, configure using single field index controls"). Deploy both via `firebase deploy --only firestore:rules,firestore:indexes`. |
