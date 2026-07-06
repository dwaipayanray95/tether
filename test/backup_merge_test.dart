import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether/models/deletion_record_model.dart';
import 'package:tether/services/backup_merge.dart';

void main() {
  group('mergeDelta', () {
    test('adds new docs not present in existing', () {
      final existing = [
        {'id': 'a', 'title': 'first'},
      ];
      final incoming = [
        {'id': 'b', 'title': 'second'},
      ];

      final result = mergeDelta(existing, incoming);

      expect(result.length, 2);
      expect(result.map((d) => d['id']), containsAll(['a', 'b']));
    });

    test('incoming wins on conflicting ids', () {
      final existing = [
        {'id': 'a', 'title': 'stale'},
      ];
      final incoming = [
        {'id': 'a', 'title': 'fresh'},
      ];

      final result = mergeDelta(existing, incoming);

      expect(result.length, 1);
      expect(result.single['title'], 'fresh');
    });

    test('empty incoming leaves existing untouched', () {
      final existing = [
        {'id': 'a', 'title': 'first'},
        {'id': 'b', 'title': 'second'},
      ];

      final result = mergeDelta(existing, []);

      expect(result.length, 2);
    });

    test('empty existing (first backup ever) returns just incoming', () {
      final incoming = [
        {'id': 'a', 'title': 'first'},
      ];

      final result = mergeDelta([], incoming);

      expect(result.length, 1);
      expect(result.single['id'], 'a');
    });
  });

  group('applyTombstones', () {
    test('removes docs matching a tombstone for the given collection', () {
      final docs = [
        {'id': 'a'},
        {'id': 'b'},
      ];
      final tombstones = [
        DeletionRecord(collection: 'todos', docId: 'a', deletedAt: DateTime.now()),
      ];

      final result = applyTombstones(docs, tombstones, 'todos');

      expect(result.length, 1);
      expect(result.single['id'], 'b');
    });

    test('ignores tombstones for a different collection', () {
      final docs = [
        {'id': 'a'},
      ];
      final tombstones = [
        DeletionRecord(
            collection: 'sticky_notes', docId: 'a', deletedAt: DateTime.now()),
      ];

      final result = applyTombstones(docs, tombstones, 'todos');

      expect(result.length, 1);
    });

    test('no tombstones is a no-op', () {
      final docs = [
        {'id': 'a'},
      ];

      final result = applyTombstones(docs, [], 'todos');

      expect(result, docs);
    });
  });

  group('sanitizeForJson', () {
    test('converts a Timestamp to an ISO-8601 string', () {
      final date = DateTime.utc(2026, 1, 15, 12, 30);
      final result = sanitizeForJson(Timestamp.fromDate(date));

      expect(result, date.toIso8601String());
    });

    test('recurses into nested maps and lists', () {
      final date = DateTime.utc(2026, 1, 15);
      final input = {
        'updatedAt': Timestamp.fromDate(date),
        'nested': {
          'readTimes': {'uid1': Timestamp.fromDate(date)},
        },
        'list': [Timestamp.fromDate(date), 'plain'],
      };

      final result = sanitizeForJson(input) as Map<String, dynamic>;

      expect(result['updatedAt'], date.toIso8601String());
      expect((result['nested'] as Map)['readTimes'],
          {'uid1': date.toIso8601String()});
      expect(result['list'], [date.toIso8601String(), 'plain']);
    });

    test('leaves plain values untouched', () {
      expect(sanitizeForJson('text'), 'text');
      expect(sanitizeForJson(42), 42);
      expect(sanitizeForJson(null), null);
    });
  });

  group('maxTimestampField', () {
    test('returns the latest of several ISO-8601 strings', () {
      final docs = [
        {'updatedAt': '2026-01-01T00:00:00.000Z'},
        {'updatedAt': '2026-03-01T00:00:00.000Z'},
        {'updatedAt': '2026-02-01T00:00:00.000Z'},
      ];

      final result = maxTimestampField(docs, 'updatedAt');

      expect(result, DateTime.parse('2026-03-01T00:00:00.000Z'));
    });

    test('returns null for an empty list', () {
      expect(maxTimestampField([], 'updatedAt'), null);
    });

    test('skips docs missing the field or with an invalid value', () {
      final docs = [
        {'title': 'no updatedAt field'},
        {'updatedAt': 'not-a-date'},
        {'updatedAt': '2026-05-01T00:00:00.000Z'},
      ];

      final result = maxTimestampField(docs, 'updatedAt');

      expect(result, DateTime.parse('2026-05-01T00:00:00.000Z'));
    });
  });

  group('computeRotationPlan', () {
    String genName(int g) => 'backup_gen$g.json.enc';
    const latestName = 'latest_backup.json.enc';

    test('first backup ever: nothing occupied, nothing to rotate', () {
      final plan = computeRotationPlan(
        latestOccupied: false,
        occupiedGenerations: 0,
        maxGenerations: 3,
        generationFileName: genName,
        latestFileName: latestName,
      );

      expect(plan, isEmpty);
    });

    test('second backup: only latest occupied, shifts it to gen1', () {
      final plan = computeRotationPlan(
        latestOccupied: true,
        occupiedGenerations: 0,
        maxGenerations: 3,
        generationFileName: genName,
        latestFileName: latestName,
      );

      expect(plan, [const RotationOp.rename(latestName, 'backup_gen1.json.enc')]);
    });

    test('partial state: latest + gen1 occupied, shifts both up one slot', () {
      final plan = computeRotationPlan(
        latestOccupied: true,
        occupiedGenerations: 1,
        maxGenerations: 3,
        generationFileName: genName,
        latestFileName: latestName,
      );

      expect(plan, [
        const RotationOp.rename('backup_gen1.json.enc', 'backup_gen2.json.enc'),
        const RotationOp.rename(latestName, 'backup_gen1.json.enc'),
      ]);
    });

    test('full state: at max generations, deletes oldest before shifting', () {
      final plan = computeRotationPlan(
        latestOccupied: true,
        occupiedGenerations: 3,
        maxGenerations: 3,
        generationFileName: genName,
        latestFileName: latestName,
      );

      expect(plan, [
        const RotationOp.delete('backup_gen3.json.enc'),
        const RotationOp.rename('backup_gen2.json.enc', 'backup_gen3.json.enc'),
        const RotationOp.rename('backup_gen1.json.enc', 'backup_gen2.json.enc'),
        const RotationOp.rename(latestName, 'backup_gen1.json.enc'),
      ]);
    });

    test('operations are ordered high-to-low so no rename overwrites an '
        'unprocessed slot', () {
      final plan = computeRotationPlan(
        latestOccupied: true,
        occupiedGenerations: 3,
        maxGenerations: 3,
        generationFileName: genName,
        latestFileName: latestName,
      );

      // The delete must come before any rename that targets the same slot,
      // and each rename's target slot must not be touched again afterward.
      final touchedTargets = <String>{};
      for (final op in plan) {
        if (op.type == RotationOpType.rename) {
          expect(touchedTargets.contains(op.to), isFalse,
              reason: '${op.to} was already written to earlier in the plan');
          touchedTargets.add(op.to!);
        }
      }
    });
  });
}
