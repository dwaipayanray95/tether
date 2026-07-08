import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether/local_db/app_database.dart';
import 'package:tether/local_db/converters.dart';

void main() {
  group('toEpochMillis', () {
    test('converts a Timestamp', () {
      final ts = Timestamp.fromDate(DateTime.utc(2024, 1, 1));
      expect(toEpochMillis(ts), DateTime.utc(2024, 1, 1).millisecondsSinceEpoch);
    });

    test('converts an ISO-8601 string', () {
      expect(toEpochMillis('2024-01-01T00:00:00.000Z'),
          DateTime.utc(2024, 1, 1).millisecondsSinceEpoch);
    });

    test('converts a DateTime', () {
      expect(toEpochMillis(DateTime.utc(2024, 1, 1)),
          DateTime.utc(2024, 1, 1).millisecondsSinceEpoch);
    });

    test('returns null for null', () {
      expect(toEpochMillis(null), isNull);
    });

    test('returns null for an unparseable string', () {
      expect(toEpochMillis('not-a-date'), isNull);
    });
  });

  group('messageRowFromFirestoreMap', () {
    test('maps a plain text message doc', () {
      final companion = messageRowFromFirestoreMap('msg1', {
        'senderId': 'ray-uid',
        'text': 'hello',
        'type': 'text',
        'sentAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1, 0, 0, 5)),
        'readBy': ['ray-uid'],
      });

      expect(companion.id.value, 'msg1');
      expect(companion.senderId.value, 'ray-uid');
      expect(companion.textContent.value, 'hello');
      expect(companion.type.value, 'text');
      expect(companion.sentAt.value, DateTime.utc(2024, 1, 1).millisecondsSinceEpoch);
      expect(companion.updatedAt.value,
          DateTime.utc(2024, 1, 1, 0, 0, 5).millisecondsSinceEpoch);
      expect(companion.readBy.value, '["ray-uid"]');
    });

    test('falls back updatedAt to sentAt when Firestore has no updatedAt yet', () {
      final companion = messageRowFromFirestoreMap('msg2', {
        'senderId': 'ray-uid',
        'text': 'hi',
        'type': 'text',
        'sentAt': '2024-01-01T00:00:00.000Z',
      });

      expect(companion.updatedAt.value, companion.sentAt.value);
    });

    test('defaults deliveryStatus to sent unless told otherwise', () {
      final companion = messageRowFromFirestoreMap('msg3', {
        'senderId': 'ray-uid',
        'text': 'hi',
        'type': 'text',
        'sentAt': '2024-01-01T00:00:00.000Z',
      });
      expect(companion.deliveryStatus.value, 'sent');

      final pending = messageRowFromFirestoreMap(
        'msg4',
        {
          'senderId': 'ray-uid',
          'text': 'hi',
          'type': 'text',
          'sentAt': '2024-01-01T00:00:00.000Z',
        },
        deliveryStatus: 'pending',
      );
      expect(pending.deliveryStatus.value, 'pending');
    });

    test('encodes reactions and readTimes maps as JSON', () {
      final companion = messageRowFromFirestoreMap('msg5', {
        'senderId': 'ray-uid',
        'text': 'hi',
        'type': 'text',
        'sentAt': '2024-01-01T00:00:00.000Z',
        'reactions': {
          '❤️': ['ray-uid']
        },
        'readTimes': {'ray-uid': '2024-01-01T00:00:05.000Z'},
      });

      expect(companion.reactions.value, contains('❤️'));
      expect(companion.readTimes.value, contains('ray-uid'));
    });
  });

  group('todoRowFromFirestoreMap', () {
    test('maps a todo doc including nested checklist', () {
      final companion = todoRowFromFirestoreMap('todo1', {
        'title': 'Buy milk',
        'isDone': false,
        'createdBy': 'ray-uid',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'checklist': [
          {'id': 'c1', 'title': 'step 1', 'isDone': true}
        ],
      });

      expect(companion.id.value, 'todo1');
      expect(companion.title.value, 'Buy milk');
      expect(companion.isDone.value, false);
      expect(companion.checklist.value, contains('step 1'));
    });
  });

  group('commentRowFromFirestoreMap', () {
    test('maps a comment doc with its parent todoId', () {
      final companion = commentRowFromFirestoreMap('c1', 'todo1', {
        'text': 'looks good',
        'authorName': 'Ray',
        'createdAt': '2024-01-01T00:00:00.000Z',
      });

      expect(companion.id.value, 'c1');
      expect(companion.todoId.value, 'todo1');
      expect(companion.textContent.value, 'looks good');
    });
  });

  group('stickyNoteRowFromFirestoreMap', () {
    test('maps a sticky note doc with Timestamp fields', () {
      final companion = stickyNoteRowFromFirestoreMap('note1', {
        'text': 'remember the milk',
        'createdBy': 'ray-uid',
        'createdByName': 'Ray',
        'colorIndex': 2,
        'createdAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
        'isArchived': false,
      });

      expect(companion.id.value, 'note1');
      expect(companion.colorIndex.value, 2);
      expect(companion.isArchived.value, false);
      expect(companion.createdAt.value, DateTime.utc(2024, 1, 1).millisecondsSinceEpoch);
    });
  });

  group('messageFromRow', () {
    // Regression test for a real production bug: jsonDecode()'s output is
    // not always exactly `Map<String, dynamic>` at the type-check level,
    // and a plain `as Map<String, dynamic>` cast on it threw
    // "_Map<dynamic, dynamic> is not a subtype of Map<String, dynamic>"
    // for every message that had reactions or read receipts set — which
    // silently killed the entire chat message list (no messages rendered
    // at all) until this was found and fixed.
    MessageRow rowWith({String? readTimes, String? reactions}) {
      return MessageRow(
        id: 'm1',
        senderId: 'ray-uid',
        textContent: 'hello',
        type: 'text',
        sentAt: DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
        readBy: '["ray-uid","aproo-uid"]',
        readTimes: readTimes,
        reactions: reactions,
        updatedAt: DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
        deliveryStatus: 'sent',
      );
    }

    test('converts a row with reactions set without throwing', () {
      final row = rowWith(reactions: '{"❤️":["ray-uid"]}');
      final message = messageFromRow(row);
      expect(message.reactions['❤️'], ['ray-uid']);
    });

    test('converts a row with readTimes set without throwing', () {
      final row = rowWith(readTimes: '{"ray-uid":"2024-01-01T00:00:05.000Z"}');
      final message = messageFromRow(row);
      expect(message.readTimes['ray-uid'], DateTime.parse('2024-01-01T00:00:05.000Z'));
    });

    test('converts a row with both reactions and readTimes set', () {
      final row = rowWith(
        readTimes: '{"ray-uid":"2024-01-01T00:00:05.000Z"}',
        reactions: '{"🔥":["ray-uid","aproo-uid"]}',
      );
      final message = messageFromRow(row);
      expect(message.reactions['🔥'], ['ray-uid', 'aproo-uid']);
      expect(message.readTimes['ray-uid'], isNotNull);
    });

    test('converts a row with neither set (the common case)', () {
      final row = rowWith();
      final message = messageFromRow(row);
      expect(message.reactions, isEmpty);
      expect(message.readTimes, isEmpty);
      expect(message.readBy, ['ray-uid', 'aproo-uid']);
    });
  });

  group('todoFromRow', () {
    Todo rowWith({String? dueDate, String? completedAt, String checklist = '[]'}) {
      return Todo(
        id: 't1',
        title: 'Buy milk',
        isDone: false,
        createdBy: 'ray-uid',
        createdAt: DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
        checklist: checklist,
        updatedAt: DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
      );
    }

    test('converts a todo with an empty checklist (the common case)', () {
      final todo = todoFromRow(rowWith());
      expect(todo.title, 'Buy milk');
      expect(todo.checklist, isEmpty);
    });

    test('converts a todo with checklist items', () {
      final row = rowWith(
          checklist: '[{"id":"c1","title":"step 1","isDone":true}]');
      final todo = todoFromRow(row);
      expect(todo.checklist.single.title, 'step 1');
      expect(todo.checklist.single.isDone, true);
    });

    test('converts null dueDate/completedAt without throwing', () {
      final todo = todoFromRow(rowWith());
      expect(todo.dueDate, isNull);
      expect(todo.completedAt, isNull);
    });
  });

  group('commentFromRow', () {
    test('converts a comment row', () {
      final row = TodoCommentRow(
        id: 'c1',
        todoId: 't1',
        textContent: 'looks good',
        authorName: 'Ray',
        createdAt: DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
      );
      final comment = commentFromRow(row);
      expect(comment.text, 'looks good');
      expect(comment.authorName, 'Ray');
    });
  });

  group('maxRawTimestampField', () {
    // Backs LocalSyncService's incremental backfill cursor — must handle
    // the mixed Timestamp/String shape a raw (pre-sanitized) Firestore
    // fetch actually has, unlike backup_merge.dart's maxTimestampField()
    // which only ever sees already-sanitized ISO strings.
    test('finds the latest of several Timestamp values', () {
      final docs = [
        {'updatedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1))},
        {'updatedAt': Timestamp.fromDate(DateTime.utc(2024, 6, 1))},
        {'updatedAt': Timestamp.fromDate(DateTime.utc(2024, 3, 1))},
      ];
      expect(maxRawTimestampField(docs, 'updatedAt'), DateTime.utc(2024, 6, 1));
    });

    test('handles a mix of Timestamp and ISO-string values', () {
      final docs = [
        {'updatedAt': '2024-01-01T00:00:00.000Z'},
        {'updatedAt': Timestamp.fromDate(DateTime.utc(2024, 6, 1))},
      ];
      expect(maxRawTimestampField(docs, 'updatedAt'), DateTime.utc(2024, 6, 1));
    });

    test('returns null for an empty list', () {
      expect(maxRawTimestampField([], 'updatedAt'), isNull);
    });

    test('skips docs missing the field', () {
      final docs = [
        {'other': 'field'},
        {'updatedAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1))},
      ];
      expect(maxRawTimestampField(docs, 'updatedAt'), DateTime.utc(2024, 1, 1));
    });
  });
}
