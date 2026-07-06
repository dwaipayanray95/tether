import 'backup_cursor_store.dart';
import 'backup_service.dart';
import 'log_service.dart';

/// Runs the backup pipeline on a "check whenever the app is opened or
/// resumed, run if it's due" cadence — the same pattern this app already
/// uses for update checks and preferences backup.
///
/// This exists because Google Sign-In's silent/lightweight auth (needed
/// for every Drive call in the backup pipeline) does not work from a
/// headless WorkManager background Worker on Android — it appears to
/// require a foreground Activity context. Verified via the Diagnostics
/// "Trigger Background Task Now" test: Firestore reads and crypto
/// succeeded every time in that background isolate, but the very first
/// Drive call failed every time with "Google Sign-In user is not
/// available." So the backup can only run reliably while the app is
/// actually in the foreground.
class ForegroundBackupScheduler {
  static const dueInterval = Duration(hours: 24);

  /// Runs a backup if enough time has passed since the last successful
  /// one. Uses the persisted cursor (not in-memory state), so this stays
  /// correctly "not due yet" even across app restarts. Pass [force]: true
  /// to bypass the interval check (used by the Diagnostics manual test).
  static Future<void> runIfDue({bool force = false}) async {
    final cursor = await BackupCursorStore().load();
    final last = cursor.lastBackupAt;

    if (!force && last != null) {
      final since = DateTime.now().difference(last);
      if (since < dueInterval) {
        LogService.log(
            'Backup: skipped (last ran ${since.inHours}h ago, due every ${dueInterval.inHours}h)');
        return;
      }
    }

    LogService.log('Backup: due, running now (force=$force)');
    final result = await BackupService().runBackup();
    LogService.log(
        'Backup: foreground-triggered run finished — success=${result.success}, ${result.message}');
  }
}
