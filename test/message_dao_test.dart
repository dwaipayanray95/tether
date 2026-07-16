import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether/local_db/app_database.dart';
import 'package:tether/local_db/daos/message_dao.dart';

/// Exercises MessageDao.fetchPage()'s pagination cursor against a real (if
/// in-memory) SQLite database — the plan explicitly flagged this as the
/// single most bug-prone mechanical change in the chat_screen.dart cutover
/// (replacing Firestore's DocumentSnapshot-based startAfter() cursor with a
/// plain sentAt epoch-millis cursor), so it gets a dedicated test rather
/// than trusting the migration by inspection alone.
void main() {
  late AppDatabase db;
  late MessageDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = MessageDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('fetchPage returns newest-first order', () async {
    await dao.upsertBatch([
      _msg('a', 100),
      _msg('b', 300),
      _msg('c', 200),
    ]);

    final page = await dao.fetchPage(50);

    expect(page.map((m) => m.id).toList(), ['b', 'c', 'a']);
  });

  test('fetchPage respects the limit', () async {
    await dao.upsertBatch([_msg('a', 100), _msg('b', 200), _msg('c', 300)]);

    final page = await dao.fetchPage(2);

    expect(page.length, 2);
    expect(page.map((m) => m.id).toList(), ['c', 'b']);
  });

  test('beforeSentAtMillis is exclusive of the cursor itself', () async {
    // Matches Firestore's startAfterDocument() being exclusive of the
    // cursor doc — a message with sentAt exactly equal to the cursor must
    // NOT reappear on the next page, or pagination would duplicate it.
    await dao.upsertBatch([_msg('a', 100), _msg('b', 200), _msg('c', 300)]);

    final page = await dao.fetchPage(50, beforeSentAtMillis: 200);

    expect(page.map((m) => m.id).toList(), ['a']);
  });

  test('paging through in fixed-size pages never skips or duplicates a message', () async {
    final all = List.generate(10, (i) => _msg('m$i', i * 10));
    await dao.upsertBatch(all);

    final seen = <String>[];
    int? cursor;
    for (var i = 0; i < 10; i++) {
      final page = await dao.fetchPage(3, beforeSentAtMillis: cursor);
      if (page.isEmpty) break;
      seen.addAll(page.map((m) => m.id));
      cursor = page.last.sentAt;
    }

    // Newest-first pagination over 10 messages, 3 at a time, should visit
    // every message exactly once.
    expect(seen.length, 10);
    expect(seen.toSet().length, 10, reason: 'no message should be duplicated across pages');
  });

  test('fetchPage on an empty table returns an empty list, not an error', () async {
    final page = await dao.fetchPage(50);
    expect(page, isEmpty);
  });

  test('deleteById removes exactly one message', () async {
    await dao.upsertBatch([_msg('a', 100), _msg('b', 200)]);
    await dao.deleteById('a');

    final page = await dao.fetchPage(50);
    expect(page.map((m) => m.id).toList(), ['b']);
  });

  test('upsertBatch updates an existing row rather than duplicating it', () async {
    await dao.upsertBatch([_msg('a', 100)]);
    await dao.upsertBatch([
      MessagesCompanion.insert(
        id: 'a',
        senderId: 'ray-uid',
        textContent: 'edited',
        type: 'text',
        sentAt: 100,
        updatedAt: 150,
      ),
    ]);

    final page = await dao.fetchPage(50);
    expect(page.length, 1);
    expect(page.single.textContent, 'edited');
  });

  group('watchLatest reactivity', () {
    test('emits new rows written by a DIFFERENT MessageDao instance wrapping the SAME AppDatabase', () async {
      // Mirrors the real app: chat_screen.dart's MessageDao and
      // local_sync_service.dart's MessageDao are two different DAO
      // instances, both wrapping AppDatabase.instance() — the same
      // pattern, reproduced here explicitly instead of trusting it works
      // because they happen to share `db` in this test file's setUp.
      final otherDao = MessageDao(db);

      final emissions = <int>[];
      final sub = dao.watchLatest(50).listen((rows) => emissions.add(rows.length));

      // Let the initial (empty) emission land.
      await Future.delayed(Duration.zero);
      expect(emissions, [0]);

      // Simulate LocalSyncService's backfill writing through a different
      // MessageDao instance, after the subscription already exists.
      await otherDao.upsertBatch([_msg('a', 100), _msg('b', 200)]);
      await Future.delayed(Duration.zero);

      expect(emissions.last, 2,
          reason: 'watchLatest() must react to writes made through a different DAO instance on the same AppDatabase');

      await sub.cancel();
    });

    test('subscribing to an empty table then inserting rows populates the stream (fresh-install / backfill race)', () async {
      // This is the exact chat_screen.dart startup sequence: subscribe to
      // watchLatest() while the table is still empty (before the
      // full-history backfill has written anything), then rows arrive.
      final rows = <List<MessageRow>>[];
      final sub = dao.watchLatest(50).listen(rows.add);

      await Future.delayed(Duration.zero);
      expect(rows.last, isEmpty);

      await dao.upsertBatch(List.generate(5, (i) => _msg('m$i', i * 10)));
      await Future.delayed(Duration.zero);

      expect(rows.last.length, 5,
          reason: 'a fresh subscription must pick up rows inserted after subscribing, not just at subscribe time');

      await sub.cancel();
    });
  });

  group('fetchSince', () {
    // Used by BackupService.runBackup() (Phase 4) as a drop-in replacement
    // for firestore_service.dart's fetchMessagesSince() — same
    // "where updatedAt > cursor" semantics, just reading the local DB.
    MessagesCompanion msgWithUpdatedAt(String id, int sentAt, int updatedAt) {
      return MessagesCompanion.insert(
        id: id,
        senderId: 'ray-uid',
        textContent: 'msg $id',
        type: 'text',
        sentAt: sentAt,
        updatedAt: updatedAt,
      );
    }

    test('null since returns everything (first backup ever)', () async {
      await dao.upsertBatch([
        msgWithUpdatedAt('a', 100, 100),
        msgWithUpdatedAt('b', 200, 200),
      ]);

      final maps = await dao.fetchSince(null);
      expect(maps.length, 2);
    });

    test('only returns rows with updatedAt strictly after the cursor', () async {
      await dao.upsertBatch([
        msgWithUpdatedAt('a', 100, 100),
        msgWithUpdatedAt('b', 200, 200),
        msgWithUpdatedAt('c', 300, 300),
      ]);

      final since = DateTime.fromMillisecondsSinceEpoch(200, isUtc: true);
      final maps = await dao.fetchSince(since);

      expect(maps.map((m) => m['id']), ['c']);
    });

    test('returned maps have Firestore-delta shape (id key, ISO string dates)', () async {
      await dao.upsertBatch([msgWithUpdatedAt('a', 100, 100)]);

      final maps = await dao.fetchSince(null);
      final map = maps.single;

      expect(map['id'], 'a');
      expect(map['sentAt'], isA<String>());
      expect(DateTime.tryParse(map['sentAt'] as String), isNotNull);
    });
  });
}

MessagesCompanion _msg(String id, int sentAt) {
  return MessagesCompanion.insert(
    id: id,
    senderId: 'ray-uid',
    textContent: 'msg $id',
    type: 'text',
    sentAt: sentAt,
    updatedAt: sentAt,
  );
}
