import 'package:drift/drift.dart';
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
  Future<List<Map<String, dynamic>>> fetchSince(DateTime? since) async {
    final query = _db.select(_db.stickyNotes);
    if (since != null) {
      query.where((s) => s.updatedAt.isBiggerThanValue(since.toUtc().millisecondsSinceEpoch));
    }
    final rows = await query.get();
    return rows.map(stickyNoteMapFromRow).toList();
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
}
