import '../local_db/app_database.dart';
import '../local_db/converters.dart';
import '../local_db/daos/comment_dao.dart';
import '../local_db/daos/message_dao.dart';
import '../local_db/daos/sticky_note_dao.dart';
import '../local_db/daos/todo_dao.dart';
import '../models/backup_snapshot_model.dart';
import 'backup_service.dart';
import 'log_service.dart';

/// Fresh-install / restore entry point: takes the already-merged
/// (Drive backup + live Firestore) [BackupSnapshot] that
/// [BackupService.restoreFromBackup] produces and writes it into the local
/// DB via the same DAO upsert path [LocalSyncService]'s live listeners use.
/// Never touches Firestore — the merge already happened in memory inside
/// [BackupService]; this only persists the result locally so the UI (which
/// reads exclusively from the local DB after Phase 2-3) can actually show
/// it, including history Firestore itself may have already purged.
class LocalDbHydrationService {
  final AppDatabase _appDb = AppDatabase.instance();

  late final MessageDao _messageDao = MessageDao(_appDb);
  late final TodoDao _todoDao = TodoDao(_appDb);
  late final CommentDao _commentDao = CommentDao(_appDb);
  late final StickyNoteDao _stickyNoteDao = StickyNoteDao(_appDb);

  /// Runs [BackupService.restoreFromBackup] and writes the result into the
  /// local DB. Returns true if a backup existed and was hydrated, false if
  /// there was nothing to restore (e.g. brand new couple with no backup
  /// yet) — callers should treat false as "nothing to do", not an error.
  Future<bool> hydrateFromBackupAndLiveGap() async {
    final snapshot = await BackupService().restoreFromBackup(dryRun: false);
    if (snapshot == null) {
      LogService.log('LocalDbHydrationService: no backup to hydrate from');
      return false;
    }

    await _hydrateMessages(snapshot);
    await _hydrateTodos(snapshot);
    await _hydrateComments(snapshot);
    await _hydrateStickyNotes(snapshot);

    LogService.log('LocalDbHydrationService: hydrated ${snapshot.messages.length} '
        'messages, ${snapshot.todos.length} todos, ${snapshot.comments.length} '
        'comments, ${snapshot.stickyNotes.length} sticky notes into local DB');
    return true;
  }

  Future<void> _hydrateMessages(BackupSnapshot snapshot) async {
    final rows = <MessagesCompanion>[];
    for (final doc in snapshot.messages) {
      final id = doc['id'] as String?;
      if (id == null) continue;
      try {
        rows.add(messageRowFromFirestoreMap(id, doc, deliveryStatus: 'sent'));
      } catch (e) {
        LogService.log('LocalDbHydrationService: failed to convert message $id: $e');
      }
    }
    if (rows.isNotEmpty) await _messageDao.upsertBatch(rows);
  }

  Future<void> _hydrateTodos(BackupSnapshot snapshot) async {
    final rows = <TodosCompanion>[];
    for (final doc in snapshot.todos) {
      final id = doc['id'] as String?;
      if (id == null) continue;
      try {
        rows.add(todoRowFromFirestoreMap(id, doc));
      } catch (e) {
        LogService.log('LocalDbHydrationService: failed to convert todo $id: $e');
      }
    }
    if (rows.isNotEmpty) await _todoDao.upsertBatch(rows);
  }

  Future<void> _hydrateComments(BackupSnapshot snapshot) async {
    final rows = <TodoCommentsCompanion>[];
    for (final doc in snapshot.comments) {
      final id = doc['id'] as String?;
      final todoId = doc['todoId'] as String?;
      if (id == null || todoId == null) continue;
      try {
        rows.add(commentRowFromFirestoreMap(id, todoId, doc));
      } catch (e) {
        LogService.log('LocalDbHydrationService: failed to convert comment $id: $e');
      }
    }
    if (rows.isNotEmpty) await _commentDao.upsertBatch(rows);
  }

  Future<void> _hydrateStickyNotes(BackupSnapshot snapshot) async {
    final rows = <StickyNotesCompanion>[];
    for (final doc in snapshot.stickyNotes) {
      final id = doc['id'] as String?;
      if (id == null) continue;
      try {
        rows.add(stickyNoteRowFromFirestoreMap(id, doc));
      } catch (e) {
        LogService.log('LocalDbHydrationService: failed to convert sticky note $id: $e');
      }
    }
    if (rows.isNotEmpty) await _stickyNoteDao.upsertBatch(rows);
  }
}
