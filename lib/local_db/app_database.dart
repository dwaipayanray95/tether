import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables/message_table.dart';
import 'tables/todo_table.dart';
import 'tables/comment_table.dart';
import 'tables/sticky_note_table.dart';

part 'app_database.g.dart';

/// The local-first source of truth for chat/todo/sticky-note UI (see
/// AGENTS.md's "Local-first architecture" section). Fed by
/// LocalSyncService's Firestore listeners and, on a fresh install,
/// LocalDbHydrationService's backup restore — never written to directly by
/// screens the way Firestore is.
@DriftDatabase(tables: [Messages, Todos, TodoComments, StickyNotes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For unit tests only — an isolated in-memory database, so DAO/pagination
  /// logic can be tested against a real (if temporary) SQLite instance
  /// instead of mocking Drift's query builder.
  AppDatabase.forTesting(super.executor);

  // Static, not per-call-site instances — every screen/service must share
  // the same open database connection, unlike e.g. GoogleDriveService()
  // which is deliberately stateless-per-instance. Access via
  // AppDatabase.instance().
  static AppDatabase? _instance;
  factory AppDatabase.instance() => _instance ??= AppDatabase();

  @override
  int get schemaVersion => 2;

  // v2: added indices on the columns every DAO actually queries/sorts on
  // (sentAt/updatedAt/createdAt/todoId) — v1 had none, so every pagination,
  // sync-delta, and per-todo-comment query was a full table scan that got
  // worse as history grew. A fresh install (schemaVersion mismatch against
  // an empty DB) goes through onCreate, which already includes the indices
  // via createAll(); onUpgrade only needs to add them to a v1 DB that
  // already has data.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createIndex(Index('messages_sent_at',
                'CREATE INDEX messages_sent_at ON messages (sent_at)'));
            await m.createIndex(Index('messages_updated_at',
                'CREATE INDEX messages_updated_at ON messages (updated_at)'));
            await m.createIndex(Index('todos_created_at',
                'CREATE INDEX todos_created_at ON todos (created_at)'));
            await m.createIndex(Index('todos_updated_at',
                'CREATE INDEX todos_updated_at ON todos (updated_at)'));
            await m.createIndex(Index('comments_todo_id',
                'CREATE INDEX comments_todo_id ON todo_comments (todo_id)'));
            await m.createIndex(Index('sticky_notes_created_at',
                'CREATE INDEX sticky_notes_created_at ON sticky_notes (created_at)'));
            await m.createIndex(Index('sticky_notes_updated_at',
                'CREATE INDEX sticky_notes_updated_at ON sticky_notes (updated_at)'));
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'tether_local.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
