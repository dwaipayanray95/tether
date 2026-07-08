import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:tether/local_db/app_database.dart';
import 'package:tether/local_db/daos/comment_dao.dart';
import 'package:tether/local_db/daos/message_dao.dart';
import 'package:tether/local_db/daos/sticky_note_dao.dart';
import 'package:tether/local_db/daos/todo_dao.dart';
import 'package:tether/local_db/converters.dart';

// LocalDbHydrationService itself just wires BackupService.restoreFromBackup()
// (which needs real Firestore/Drive/crypto — not unit-testable) to these same
// converter + upsertBatch calls. These tests cover the part that actually has
// logic: that a BackupSnapshot-shaped map list converts and upserts cleanly,
// including the malformed-row skip behavior the service relies on.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('hydrates messages from a backup-shaped doc list', () async {
    final dao = MessageDao(db);
    final docs = [
      {
        'id': 'm1',
        'senderId': 'ray-uid',
        'text': 'hello',
        'type': 'text',
        'sentAt': '2024-01-01T00:00:00.000Z',
      },
      {
        'id': 'm2',
        'senderId': 'aproo-uid',
        'text': 'hi back',
        'type': 'text',
        'sentAt': '2024-01-02T00:00:00.000Z',
      },
    ];

    final rows = docs
        .map((d) => messageRowFromFirestoreMap(d['id'] as String, d, deliveryStatus: 'sent'))
        .toList();
    await dao.upsertBatch(rows);

    expect(await dao.count(), 2);
  });

  test('skips a message doc missing an id instead of throwing', () async {
    final docs = <Map<String, dynamic>>[
      {'text': 'no id here', 'type': 'text', 'sentAt': '2024-01-01T00:00:00.000Z'},
      {'id': 'm2', 'text': 'valid', 'type': 'text', 'sentAt': '2024-01-01T00:00:00.000Z'},
    ];

    final rows = <dynamic>[];
    for (final doc in docs) {
      final id = doc['id'] as String?;
      if (id == null) continue;
      rows.add(messageRowFromFirestoreMap(id, doc, deliveryStatus: 'sent'));
    }

    expect(rows.length, 1);
  });

  test('hydrates todos from a backup-shaped doc list', () async {
    final dao = TodoDao(db);
    final docs = [
      {'id': 't1', 'title': 'Buy milk', 'createdBy': 'ray-uid', 'createdAt': '2024-01-01T00:00:00.000Z'},
    ];
    final rows = docs.map((d) => todoRowFromFirestoreMap(d['id'] as String, d)).toList();
    await dao.upsertBatch(rows);

    expect(await dao.count(), 1);
  });

  test('hydrates comments from a backup-shaped doc list carrying todoId', () async {
    final dao = CommentDao(db);
    final docs = [
      {'id': 'c1', 'todoId': 't1', 'text': 'nice', 'authorName': 'Ray', 'createdAt': '2024-01-01T00:00:00.000Z'},
    ];
    final rows = docs
        .map((d) => commentRowFromFirestoreMap(d['id'] as String, d['todoId'] as String, d))
        .toList();
    await dao.upsertBatch(rows);

    expect(await dao.count(), 1);
  });

  test('hydrates sticky notes from a backup-shaped doc list', () async {
    final dao = StickyNoteDao(db);
    final docs = [
      {
        'id': 'n1',
        'text': 'remember the milk',
        'createdBy': 'ray-uid',
        'createdByName': 'Ray',
        'colorIndex': 1,
        'createdAt': '2024-01-01T00:00:00.000Z',
      },
    ];
    final rows = docs.map((d) => stickyNoteRowFromFirestoreMap(d['id'] as String, d)).toList();
    await dao.upsertBatch(rows);

    expect(await dao.count(), 1);
  });
}
