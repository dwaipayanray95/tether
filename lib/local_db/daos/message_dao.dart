import 'package:drift/drift.dart';
import '../app_database.dart';
import '../converters.dart';

/// All local-DB access for messages funnels through here — both
/// LocalSyncService (live Firestore echo) and LocalDbHydrationService
/// (fresh-install backup restore) call upsertBatch(), so dedup-by-id
/// semantics live in exactly one place.
class MessageDao {
  final AppDatabase _db;
  MessageDao(this._db);

  /// Newest [limit] messages, live — mirrors today's messageStream()
  /// (Firestore snapshot of the newest N docs), just backed by Drift's
  /// .watch() instead. Re-emits the full row set on any change (insert,
  /// reaction, read receipt), same reconciliation shape chat_screen.dart's
  /// _onStreamUpdate() already expects.
  Stream<List<MessageRow>> watchLatest(int limit) {
    final query = _db.select(_db.messages)
      ..orderBy([(m) => OrderingTerm.desc(m.sentAt)])
      ..limit(limit);
    return query.watch();
  }

  /// One-shot page fetch for pagination ("load more" scrolling toward
  /// older messages) — mirrors fetchMessagePage's startAfter(cursor)
  /// semantics using a plain sentAt cursor instead of a DocumentSnapshot.
  /// Exclusive of [beforeSentAtMillis] (strictly older), matching
  /// Firestore's startAfterDocument() being exclusive of the cursor doc.
  Future<List<MessageRow>> fetchPage(int limit, {int? beforeSentAtMillis}) {
    final query = _db.select(_db.messages)
      ..orderBy([(m) => OrderingTerm.desc(m.sentAt)])
      ..limit(limit);
    if (beforeSentAtMillis != null) {
      query.where((m) => m.sentAt.isSmallerThanValue(beforeSentAtMillis));
    }
    return query.get();
  }

  /// All messages, for local search — only trustworthy once the full-
  /// history backfill (see LocalSyncService) has actually completed.
  Future<List<MessageRow>> fetchAll() =>
      (_db.select(_db.messages)
            ..orderBy([(m) => OrderingTerm.desc(m.sentAt)]))
          .get();

  Future<int> count() async {
    final rows = await _db.select(_db.messages).get();
    return rows.length;
  }

  /// Firestore-delta-shaped maps for backup_service.dart's runBackup() —
  /// same "where updatedAt > cursor" semantics as
  /// firestore_service.dart's fetchMessagesSince(), just reading the local
  /// DB (already fully synced by LocalSyncService) instead of Firestore
  /// directly. A null [since] means "everything" (first backup ever).
  Future<List<Map<String, dynamic>>> fetchSince(DateTime? since) async {
    final query = _db.select(_db.messages);
    if (since != null) {
      query.where((m) => m.updatedAt.isBiggerThanValue(since.toUtc().millisecondsSinceEpoch));
    }
    final rows = await query.get();
    return rows.map(messageMapFromRow).toList();
  }

  Future<void> upsertBatch(List<MessagesCompanion> rows) async {
    if (rows.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.messages, rows);
    });
  }

  Future<void> deleteById(String id) =>
      (_db.delete(_db.messages)..where((m) => m.id.equals(id))).go();

  Future<void> updateDeliveryStatus(String id, String status) =>
      (_db.update(_db.messages)..where((m) => m.id.equals(id)))
          .write(MessagesCompanion(deliveryStatus: Value(status)));
}
