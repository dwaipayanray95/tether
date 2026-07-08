import 'package:shared_preferences/shared_preferences.dart';

/// Persists the local-DB message backfill cursor on-device — the "newest
/// updatedAt actually backfilled" timestamp, so
/// LocalSyncService._backfillFullMessageHistory() only fetches what's
/// changed since last time instead of re-reading full message history from
/// Firestore on every single app launch. Same per-device, SharedPreferences-
/// backed pattern as BackupCursorStore, deliberately kept separate since
/// this cursor tracks a different thing (local-DB sync freshness) than the
/// backup pipeline's own cursor (Drive backup freshness).
class LocalSyncCursorStore {
  // Bumped to v2: v1-era devices may have had real messages incorrectly
  // deleted from the local DB by a bug in the windowed messages listener
  // (see LocalSyncService._watchMessages — `removed` doc-changes from a
  // `.limit(50)` query were wrongly treated as real deletions). Discarding
  // the v1 cursor forces exactly one more full backfill on next launch,
  // which re-adds anything that bug erased. Safe to do once; not a pattern
  // to repeat for future unrelated fixes.
  static const _key = 'local_sync_backfill_cursor_v2';

  Future<DateTime?> loadMessagesCursor() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_key);
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  Future<void> saveMessagesCursor(DateTime cursor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, cursor.toUtc().toIso8601String());
  }
}
