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
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'tether_local.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
