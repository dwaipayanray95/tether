import 'package:drift/drift.dart';
import '../../services/log_service.dart';
import '../app_database.dart';
import '../converters.dart';

class StickyNoteDao {
  final AppDatabase _db;
  StickyNoteDao(this._db);

  /// Full-collection live stream — mirrors today's stickyNotesStream().
  Stream<List<StickyNote>> watchAll() => (_db.select(_db.stickyNotes)
        ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
      .watch();

  Future<int> count() async =>
      (await _db.select(_db.stickyNotes).get()).length;

  /// Firestore-delta-shaped maps for backup_service.dart's runBackup() —
  /// same semantics as firestore_service.dart's fetchStickyNotesSince().
  /// Converts row-by-row rather than a single .map().toList() — this feeds
  /// the backup pipeline, so one malformed row must not abort the entire
  /// backup run for every sticky note.
  Future<List<Map<String, dynamic>>> fetchSince(DateTime? since) async {
    final query = _db.select(_db.stickyNotes);
    if (since != null) {
      query.where((s) => s.updatedAt.isBiggerThanValue(since.toUtc().millisecondsSinceEpoch));
    }
    final rows = await query.get();
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      try {
        result.add(stickyNoteMapFromRow(row));
      } catch (e) {
        LogService.log('StickyNoteDao: failed to convert row ${row.id} for backup: $e');
      }
    }
    return result;
  }

  Future<void> upsertBatch(List<StickyNotesCompanion> rows) async {
    if (rows.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.stickyNotes, rows);
    });
  }

  Future<void> deleteById(String id) => (_db.delete(_db.stickyNotes)
        ..where((s) => s.id.equals(id)))
      .go();

  /// Single statement for N deletes instead of N sequential awaited
  /// statements — see TodoDao.deleteByIds for why.
  Future<void> deleteByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    await (_db.delete(_db.stickyNotes)..where((s) => s.id.isIn(ids))).go();
  }
}
