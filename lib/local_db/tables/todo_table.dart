import 'package:drift/drift.dart';

/// Mirrors TodoItem.toMap()/fromMap() (lib/models/todo_model.dart). `checklist`
/// is stored as a JSON-encoded list of {id, title, isDone} maps, same shape
/// ChecklistItem.toMap() already produces. `updatedAt` is a local sync-cursor
/// bookkeeping column, same convention as message_table.dart.
class Todos extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get details => text().nullable()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  TextColumn get createdBy => text()();
  IntColumn get createdAt => integer()();
  IntColumn get dueDate => integer().nullable()();
  TextColumn get assignedTo => text().nullable()();
  TextColumn get priority => text().nullable()();
  IntColumn get completedAt => integer().nullable()();
  TextColumn get checklist => text().withDefault(const Constant('[]'))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
