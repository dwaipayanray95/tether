import 'package:drift/drift.dart';

/// Mirrors the sticky_notes Firestore doc shape used in firestore_service.dart
/// (addStickyNote/archiveStickyNote/etc.) and sticky_board.dart — there is no
/// dedicated model class for sticky notes today (the screen reads raw
/// QuerySnapshot data directly), so this table is the first place that shape
/// gets named explicitly.
class StickyNotes extends Table {
  TextColumn get id => text()();
  TextColumn get textContent => text().named('text')();
  TextColumn get createdBy => text()();
  TextColumn get createdByName => text()();
  IntColumn get colorIndex => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get archivedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
