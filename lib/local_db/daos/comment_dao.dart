import 'package:drift/drift.dart';
import '../../models/comment_model.dart';
import '../../services/log_service.dart';
import '../app_database.dart';
import '../converters.dart';

class CommentDao {
  final AppDatabase _db;
  CommentDao(this._db);

  /// Per-todo live stream — mirrors today's commentStream(coupleId, todoId),
  /// called on demand per open todo detail sheet, not materialized globally.
  Stream<List<TodoCommentRow>> watchForTodo(String todoId) {
    final query = _db.select(_db.todoComments)
      ..where((c) => c.todoId.equals(todoId))
      ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]);
    return query.watch();
  }

  /// Same as watchForTodo(), converted to the app's TodoComment model.
  Stream<List<TodoComment>> watchForTodoAsModels(String todoId) =>
      watchForTodo(todoId).map((rows) {
        final result = <TodoComment>[];
        for (final row in rows) {
          try {
            result.add(commentFromRow(row));
          } catch (e) {
            LogService.log('CommentDao: failed to convert row ${row.id} to TodoComment: $e');
          }
        }
        return result;
      });

  Future<int> count() async =>
      (await _db.select(_db.todoComments).get()).length;

  /// Firestore-delta-shaped maps for backup_service.dart's runBackup() —
  /// same semantics as firestore_service.dart's fetchCommentsSince()
  /// (createdAt as cursor, not updatedAt — comments are immutable after
  /// creation).
  /// Converts row-by-row rather than a single .map().toList() — this feeds
  /// the backup pipeline, so one malformed row must not abort the entire
  /// backup run for every comment.
  Future<List<Map<String, dynamic>>> fetchSince(DateTime? since) async {
    final query = _db.select(_db.todoComments);
    if (since != null) {
      query.where((c) => c.createdAt.isBiggerThanValue(since.toUtc().millisecondsSinceEpoch));
    }
    final rows = await query.get();
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      try {
        result.add(commentMapFromRow(row));
      } catch (e) {
        LogService.log('CommentDao: failed to convert row ${row.id} for backup: $e');
      }
    }
    return result;
  }

  Future<void> upsertBatch(List<TodoCommentsCompanion> rows) async {
    if (rows.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.todoComments, rows);
    });
  }

  Future<void> deleteById(String id) => (_db.delete(_db.todoComments)
        ..where((c) => c.id.equals(id)))
      .go();

  /// Single statement for N deletes instead of N sequential awaited
  /// statements — see TodoDao.deleteByIds for why.
  Future<void> deleteByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    await (_db.delete(_db.todoComments)..where((c) => c.id.isIn(ids))).go();
  }
}
