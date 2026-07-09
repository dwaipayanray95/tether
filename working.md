# Working Log — Local-First Architecture Migration

Running progress log for the local-first on-device database effort. For the
architecture reference itself (what exists, how it fits together), see
AGENTS.md's "Local-First Architecture" section — this file is the
chronological journal: what's been done, in what order, and why, plus open
questions raised along the way. Plan file: `/Users/rayr/.claude/plans/delegated-zooming-lemur.md`.

## Why this effort exists

Tether's chat/todo screens read directly from live Firestore streams. A
fresh install has no way to display full history — the Drive backup exists,
but nothing ever loaded it into anything the UI reads from. The user wants:
a local on-device database as the single source of truth the UI reads from;
Firestore reduced to a pure real-time sync relay between the two partners'
devices; the Drive backup remains the permanent full-history archive.

Explicitly out of scope for this effort: the 90-day Firestore purge doesn't
exist yet (confirmed during planning — no Cloud Function or scheduled job
purges anything anywhere in this repo). Building the local DB is worthwhile
on its own merits regardless (instant local search, offline reads); the
purge job is a separate, later effort.

## Progress

- **Phase 0 — scaffolding.** `lib/local_db/` created: `app_database.dart`
  (drift, opens `tether_local.sqlite`), four tables mirroring each model's
  shape. Zero behavior change, verified via `flutter analyze`/`build` only.

- **Phase 1 — sync engine in shadow mode.** `local_sync_service.dart`
  listens to Firestore the same way screens already did, writes into Drift
  instead. Diagnostics got an "Inspect Local DB" tile to compare local vs.
  live Firestore counts. **User-verified on device:** 1115+ messages
  backfilled and confirmed matching.

- **Phase 2 — chat_screen.dart cutover.** Pagination, live window, and
  search moved to `MessageDao`. `sendMessage()` switched from `.add()` to
  `.doc(id).set()` so the client UUID becomes the real Firestore id (needed
  for the optimistic local insert on send). Full message delivery status
  (pending → sent → delivered → read) built, using Firestore's
  `hasPendingWrites` metadata — no custom retry/outbox needed.

  **Bugs found during device testing, in order:**
  1. `ListTile`/`DecoratedBox` ink-splash warning — pre-existing in
     `diagnostics_screen.dart`, `settings_screen.dart`, `todo_screen.dart`.
     Fixed by moving background color onto `Material` instead of the outer
     `DecoratedBox`.
  2. "Multiple heroes share the same tag" — first attempted fix (unique
     `heroTag` string on the one `FloatingActionButton` in the app) did
     **not** work. Root cause: a known Flutter/`IndexedStack` quirk where
     even a uniquely-tagged Hero can be "found twice" by Flutter's own tree
     traversal when `IndexedStack` keeps multiple `Scaffold`s mounted at
     once. Real fix: `heroTag: null`, removing the FAB from Hero handling
     entirely.
  3. **Chat showed zero messages after the cutover** — the serious one.
     Root cause: `messageFromRow()` used bare `{}` as the fallback for null
     `reactions`/`readTimes`. In Dart, an untyped `{}` map literal defaults
     to `Map<dynamic, dynamic>` at runtime, not `Map<String, dynamic>`, even
     sitting inside a `Map<String, dynamic>` literal. `Message.fromMap()`'s
     `as Map<String, dynamic>?` cast on that throws — and since row
     conversion was a single `.map().toList()`, ONE throwing row killed the
     *entire* list. This hit nearly every message, including any brand-new
     one just sent (new messages always start with empty reactions/read
     receipts). Reproduced in a unit test first, then fixed by explicitly
     typing the fallback (`<String, dynamic>{}`) and converting row-by-row
     with per-row try/catch + logging, so one bad row is skipped and logged
     instead of taking the screen down. Regression-tested in
     `test/local_sync_merge_test.dart`.

  **User-verified on device after the fix:** reading and sending both work.

- **Phase 3 — todo_screen.dart / sticky_board.dart cutover.** Same DAO
  pattern, defensive row-by-row conversion applied from the start this time
  (lesson from Phase 2's bug). `sticky_board.dart` has no dedicated model —
  uses the Drift-generated `StickyNote` row directly, reading typed fields
  instead of `doc['field']` map access. Notification scheduling confirmed
  unaffected (`todo.id`/decrypted-title flow unchanged). **User-verified on
  device:** todos, comments, and sticky notes all work correctly.

- **Phase 4 — BackupService data-source switch.** `runBackup()`'s four
  delta fetches now read the local DB (`fetchSince()` on each DAO) instead
  of Firestore directly. New `*MapFromRow()` functions in `converters.dart`
  produce the same Firestore-delta shape (`'id'` key, ISO-8601 string
  dates) the existing pure merge functions already expect, so
  `backup_merge.dart` needed zero changes. `_verifyIntegrity()` deliberately
  left pointed at live Firestore, not the local copy — see the design
  discussion below for why. **User-verified on device:** "Run Backup Now"
  and "Inspect Backup State" both confirmed working.

- **Post-Phase-4 fix: incremental message backfill.** User asked whether
  restarts could be made faster now that everything loads via the local
  DB, floating the idea of pre-decrypting/caching everything since the
  E2EE key is available. Corrected that specific idea — the local DB
  deliberately stores ciphertext only, matching Firestore, and persisting
  a decrypted cache would weaken that posture for a gain that's already
  negligible (per-message decrypt is cheap and already lazy/on-demand).
  But checking the premise surfaced a real, separate problem:
  `_backfillFullMessageHistory()` was unconditionally fetching the
  *entire* message history from Firestore on every single app launch,
  forever — not just fresh installs — directly feeding the "29k reads/day"
  cost concern flagged earlier in the project, long before any of this
  local-first work started. Fixed with a new `LocalSyncCursorStore`
  (persists the newest backfilled `updatedAt`, SharedPreferences-backed,
  same pattern as `BackupCursorStore` but a deliberately separate cursor)
  and a new pure helper `maxRawTimestampField()` in `converters.dart` to
  compute it from a raw Firestore fetch. Subsequent launches now only
  fetch the delta. 4 new tests.

- **Phase 5 — fresh-install hydration.** New `LocalDbHydrationService`
  wraps the existing `BackupService.restoreFromBackup()` (unchanged — still
  merges the Drive backup with live Firestore in memory, live wins) and
  writes the merged result into the local DB via the same converter
  functions + DAO `upsertBatch()` calls the live sync engine already uses.
  This is the piece that was missing since Phase 0: `restoreFromBackup()`
  always computed the right merged data, but nothing ever kept it anywhere
  — it got returned to the caller and thrown away after seeding the backup
  cursor. Now a fresh install actually ends up with Firestore-purged
  history sitting in the local DB the chat/todo screens read from, closing
  the gap described at the top of this file. Never writes back to
  Firestore, per the "Firestore stays a rolling live relay, never re-seeded
  from the archive" rule established earlier. `main_shell.dart`'s
  `_runFullHistoryRestore()` now calls this instead of `BackupService`
  directly. 6 new tests in `test/local_db_hydration_test.dart` covering all
  four tables plus the missing-id skip path. `flutter analyze`/`flutter
  test` (58/59 passing — same 1 pre-existing unrelated `widget_test.dart`
  smoke-test failure noted since Phase 0)/`flutter build apk --debug` all
  verified. **This closes out the plan from `delegated-zooming-lemur.md` —
  Phase 6 (cleanup) is optional and low priority, and the 90-day purge job
  remains a deliberately separate, later effort.**

- **Post-Phase-5 fix: found via actual device testing of "Inspect Local
  DB."** Messages showed a small, permanent deficit vs. live Firestore
  (1130 vs 1132) that didn't recover even after waiting or restarting.
  Root cause: the messages live listener's query is windowed to the most
  recent 50 (`.limit(50)`) — when a new message arrives and pushes the
  oldest of that 50 out of the result set, Firestore reports that as a
  `removed` doc-change, indistinguishable at the API level from a real
  delete unless you already know the query is windowed. The listener
  treated it as a real delete and erased that message from the local DB —
  meaning every message sent, ever, quietly deleted one older message from
  the local copy. Since there's no `deleteMessage()` anywhere in the app,
  `removed` on this listener can never mean a legitimate delete, so the
  fix is simply to stop honoring it there. Bumped the backfill cursor's
  storage key to force one self-healing full re-fetch on next launch
  (existing devices' cursors had already advanced past the erased
  messages, so without this they'd never come back). Also fixed 2 more
  un-tagged `FloatingActionButton`s (chat's scroll-to-bottom button,
  home's snap-send button) causing the same Hero collision documented in
  Phase 2 — missed earlier because that investigation assumed only one FAB
  existed in the whole app. **Lesson for next time:** a small,
  non-converging count mismatch in "Inspect Local DB" is a real signal
  worth chasing, not noise — this one turned out to be an actively
  worsening data-loss bug, not a timing artifact.

  **User-verified on device:** confirmed the messages listener fix and Hero
  fix both hold — the self-healing full re-backfill ran on first launch
  after the cursor-key bump (1134 messages, matching live Firestore), and
  navigating between tabs after sending a message no longer throws the
  Hero collision error. Separately, a full fresh install (uninstall +
  reinstall) was tested end-to-end and confirmed working: E2EE PIN
  restore, chat/todo/sticky-note history all present via
  `LocalDbHydrationService`, no errors. **This is the final verification
  step for the entire local-first migration (Phases 0-5) — the plan in
  `delegated-zooming-lemur.md` is now complete and confirmed working on a
  real device, not just via unit tests and `flutter analyze`/`build`.**

## Design discussion: why convert dates at all? (asked mid-Phase-4)

**The question:** local DB rows store dates as epoch-millis integers, but
the backup pipeline needs ISO-8601 strings — isn't that an added
back-and-forth conversion caused by introducing the local DB? Should the
local DB just store data the way Firestore does, or should the backup
target the local DB's format instead, so nothing needs converting?

**Short answer: this conversion isn't new — it already existed before the
local DB, and it exists because Firestore itself has no single consistent
format to copy.** Firestore already stores dates inconsistently depending
on the field: messages' `sentAt` is a literal ISO-8601 string (written that
way in `firestore_service.dart`'s `sendMessage()`), messages' `updatedAt`
and sticky notes' `createdAt`/`updatedAt` are native Firestore `Timestamp`
objects (from `FieldValue.serverTimestamp()`), and todos' dates are ISO
strings again. `sanitizeForJson()` already existed, before this session's
local-DB work, specifically to normalize that inconsistency into one
format (ISO strings) for the backup JSON blob and for the app's own model
classes (`Message.fromMap()`/`TodoItem.fromMap()` have expected ISO
strings for years, independent of anything to do with the local DB).

So "tune the local DB to match Firebase" isn't actually available as an
option — there's no single Firebase format; matching it would mean baking
Firestore's own inconsistency (mixed Timestamp/string per field) into the
local DB, which is strictly worse, not simpler.

**Why epoch-millis ints for the local DB specifically, then, instead of
ISO strings (which actually IS a real option worth weighing)?**

- *Storage:* an INTEGER column is typically 6-8 bytes; an ISO-8601 string
  is 24 bytes as TEXT — roughly 3-4x larger per date field, compounded
  across every indexed timestamp column (`sentAt`, `updatedAt`,
  `createdAt`) on every row.
- *Sort/filter performance:* SQLite compares integers numerically — the
  cheapest possible comparison. ISO-8601 strings *do* sort correctly
  lexicographically (they're specifically designed for that), so this
  isn't a correctness difference, just a small constant-factor CPU cost
  difference per comparison during pagination/backup-delta queries.
- *Realistic scale check:* for a 2-person couples app, this is genuinely
  small in absolute terms — thousands of rows, not millions. The int
  choice is the right default for a data layer this central, but the
  honest answer is neither choice would be a bottleneck at this app's
  actual scale.

**Where the "load-bearing, not cosmetic" line came from:** this refers to
the *model layer* (`Message.fromMap()` etc.) requiring `DateTime.parse()`
on a String — that expectation predates the local DB by a long way. If the
local DB stored ISO strings instead of ints, the epoch→ISO conversion step
specifically would disappear, and `fetchSince()` could hand column values
straight through. That IS a viable simplification, weighed below.

**Recommendation: keep the current design (ints in the local DB, thin
converter functions at each boundary) rather than switching to ISO
strings in the local DB.** Reasoning:
1. The conversion cost is a handful of `DateTime.fromMillisecondsSinceEpoch()`/
   `.toIso8601String()` calls per row, during backup runs that happen at
   most once every 24 hours in batches of at most a few hundred rows —
   this is microseconds of total added time, not a meaningful cost.
2. Pagination (`MessageDao.fetchPage`'s `beforeSentAtMillis` cursor) is a
   genuinely hot, latency-sensitive path (fires on every scroll-triggered
   page load) where the int representation is a real, if small, win — and
   it's already built, tested, and proven correct (7 dedicated pagination
   tests).
3. Three layers (Firestore, the JSON backup, the local DB) each keep the
   storage format best suited to their own primary job, with small, well-
   tested adapter functions translating at the boundaries — a standard,
   sound pattern. Forcing one universal format would mean either
   degrading the local DB's pagination performance, or migrating
   Firestore's actual stored data (touching live production data, for
   values genuinely too small to matter).

**On "does it build and tally with Firebase for missing entries upon
restoring":** yes — that's exactly what `BackupService.restoreFromBackup()`
already does today (merges the Drive backup with a full live-Firestore
fetch, live wins conflicts), and Phase 5 (fresh-install hydration) is
specifically about writing that merged result into the local DB rather
than discarding it as it does today.
