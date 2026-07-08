import 'package:drift/drift.dart';

/// Mirrors TodoComment.toMap()/fromMap() (lib/models/comment_model.dart).
/// `todoId` identifies the parent todo (comments/{todoId}/... in Firestore)
/// — indexed, not a real foreign key, since comments can arrive via the sync
/// listener before or after their parent todo row exists locally. Comments
/// are immutable after creation (matching firestore_service.dart's existing
/// comment_stream design), so there's no updatedAt bookkeeping column here —
/// createdAt alone is already a valid sync cursor, same as the backup
/// pipeline already assumes for comments.
///
/// @DataClassName renames the generated row class to TodoCommentRow — Drift's
/// default would collide with the app's own TodoComment model.
@DataClassName('TodoCommentRow')
class TodoComments extends Table {
  TextColumn get id => text()();
  TextColumn get todoId => text()();
  TextColumn get textContent => text().named('text')();
  TextColumn get authorName => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
