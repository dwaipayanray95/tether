import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/backup_cursor_model.dart';

/// Persists the local backup-sync cursor on-device.
///
/// This is intentionally per-device, not shared via Firestore: each
/// partner's device backs up to their own personal Google Drive
/// (Drive access is scoped to whichever account is signed in), so there's
/// no shared "one true cursor" to coordinate between two devices.
class BackupCursorStore {
  static const _key = 'backup_cursor_v1';

  Future<BackupCursor> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const BackupCursor();
    return BackupCursor.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(BackupCursor cursor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(cursor.toJson()));
  }
}
