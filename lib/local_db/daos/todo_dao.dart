import 'package:drift/drift.dart';
import '../../models/todo_model.dart';
import '../../services/log_service.dart';
import '../app_database.dart';
import '../converters.dart';

class TodoDao {
  final AppDatabase _db;
  TodoDao(this._db);

  /// Full-collection live stream — mirrors today's todoStream() (no
  /// pagination on the todo screen, matching its existing StreamBuilder).
  Stream<List<Todo>> watchAll() =>
      (_db.select(_db.todos)..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch();

  /// Same as watchAll(), converted to the app's TodoItem model — what
  /// todo_screen.dart actually consumes. Converts row-by-row rather than
  /// via a single .map().toList(), same reasoning as
  /// chat_screen.dart's _applyRows(): one bad row must not take down the
  /// whole list along with it (see the real production bug that hit
  /// exactly this pattern for messages).
  Stream<List<TodoItem>> watchAllAsModels() => watchAll().map((rows) {
        final result = <TodoItem>[];
        for (final row in rows) {
          try {
            result.add(todoFromRow(row));
          } catch (e) {
            LogService.log('TodoDao: failed to convert row ${row.id} to TodoItem: $e');
          }
        }
        return result;
      });

  Stream<Todo?> watchById(String id) =>
      (_db.select(_db.todos)..where((t) => t.id.equals(id)))
          .watchSingleOrNull();

  Stream<TodoItem?> watchByIdAsModel(String id) => watchById(id).map((row) {
        if (row == null) return null;
        try {
          return todoFromRow(row);
        } catch (e) {
          LogService.log('TodoDao: failed to convert row ${row.id} to TodoItem: $e');
          return null;
        }
      });

  Future<int> count() async => (await _db.select(_db.todos).get()).length;

  /// Firestore-delta-shaped maps for backup_service.dart's runBackup() —
  /// same semantics as firestore_service.dart's fetchTodosSince().
  Future<List<Map<String, dynamic>>> fetchSince(DateTime? since) async {
    final query = _db.select(_db.todos);
    if (since != null) {
      query.where((t) => t.updatedAt.isBiggerThanValue(since.toUtc().millisecondsSinceEpoch));
    }
    final rows = await query.get();
    return rows.map(todoMapFromRow).toList();
  }

  Future<void> upsertBatch(List<TodosCompanion> rows) async {
    if (rows.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.todos, rows);
    });
  }

  Future<void> deleteById(String id) =>
      (_db.delete(_db.todos)..where((t) => t.id.equals(id))).go();
}
