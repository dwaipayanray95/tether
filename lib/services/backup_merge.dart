import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/deletion_record_model.dart';

/// Pure data-transform functions for the backup pipeline. Deliberately free
/// of any live Firestore/Drive/crypto network dependency so they can be
/// unit tested directly — Timestamp is just a plain value type here, no
/// connection needed to construct or convert one.

/// Recursively converts any [Timestamp] values into ISO-8601 strings.
/// Firestore read results contain native Timestamp objects wherever a doc
/// has a `FieldValue.serverTimestamp()` field, and those aren't
/// JSON-serializable as-is — this must run on every doc before it's
/// merged into a backup snapshot that gets `jsonEncode`d.
dynamic sanitizeForJson(dynamic value) {
  // Timestamp.toDate() returns a local-time DateTime with no UTC tag, so
  // without normalizing here the resulting ISO string's offset would
  // depend on whichever device produced it — ambiguous once compared
  // across two partners' devices in different timezones.
  if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
  if (value is Map) {
    return value.map((k, v) => MapEntry(k as String, sanitizeForJson(v)));
  }
  if (value is List) {
    return value.map(sanitizeForJson).toList();
  }
  return value;
}

/// Merges a delta of newly-fetched docs into an existing backup list for
/// one collection. Docs are matched by their 'id' field; [incoming] wins
/// on conflict since it was fetched more recently than [existing].
List<Map<String, dynamic>> mergeDelta(
  List<Map<String, dynamic>> existing,
  List<Map<String, dynamic>> incoming,
) {
  final byId = <String, Map<String, dynamic>>{};
  for (final doc in existing) {
    byId[doc['id'] as String] = doc;
  }
  for (final doc in incoming) {
    byId[doc['id'] as String] = doc;
  }
  return byId.values.toList();
}

/// Removes any docs matching a tombstone recorded for [collectionName].
/// Cursor-based delta queries never see deletions (a removed doc just
/// stops appearing), so tombstones are the only way to apply removals to
/// the backup copy without re-reading the entire live collection.
List<Map<String, dynamic>> applyTombstones(
  List<Map<String, dynamic>> docs,
  List<DeletionRecord> tombstones,
  String collectionName,
) {
  final deletedIds = tombstones
      .where((t) => t.collection == collectionName)
      .map((t) => t.docId)
      .toSet();
  if (deletedIds.isEmpty) return docs;
  return docs.where((d) => !deletedIds.contains(d['id'])).toList();
}

/// Returns the latest value of [field] across [docs] (already sanitized
/// to ISO-8601 strings via [sanitizeForJson]), or null if none are present.
/// Used to advance a collection's sync cursor to the newest timestamp
/// actually observed in a fetched delta, rather than the device's local
/// clock — avoiding any device/server clock-skew gap that could cause a
/// doc to be missed on the next backup run.
DateTime? maxTimestampField(List<Map<String, dynamic>> docs, String field) {
  DateTime? latest;
  for (final doc in docs) {
    final raw = doc[field];
    if (raw is! String) continue;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) continue;
    if (latest == null || parsed.isAfter(latest)) latest = parsed;
  }
  return latest;
}

enum RotationOpType { delete, rename }

class RotationOp {
  final RotationOpType type;
  final String from;
  final String? to;

  const RotationOp.delete(this.from)
      : type = RotationOpType.delete,
        to = null;

  const RotationOp.rename(this.from, String toName)
      : type = RotationOpType.rename,
        to = toName;

  @override
  String toString() => type == RotationOpType.delete
      ? 'delete($from)'
      : 'rename($from -> $to)';

  @override
  bool operator ==(Object other) =>
      other is RotationOp &&
      other.type == type &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(type, from, to);
}

/// Computes the sequence of Drive file operations needed to rotate backup
/// generations before promoting a new backup, given which generation
/// slots are currently occupied.
///
/// Slot 0 is the current "latest" backup; slots 1..maxGenerations are the
/// rotated prior generations. The plan must be applied in the returned
/// order (highest slot first) so a rename never overwrites a slot that
/// hasn't been processed yet. Once [maxGenerations] would be exceeded, the
/// oldest generation is deleted instead of shifted further.
List<RotationOp> computeRotationPlan({
  required bool latestOccupied,
  required int occupiedGenerations,
  required int maxGenerations,
  required String Function(int generation) generationFileName,
  required String latestFileName,
}) {
  final ops = <RotationOp>[];
  String slotName(int slot) =>
      slot == 0 ? latestFileName : generationFileName(slot);
  bool occupied(int slot) =>
      slot == 0 ? latestOccupied : slot <= occupiedGenerations;

  for (var i = maxGenerations; i >= 1; i--) {
    if (i == maxGenerations && occupied(i)) {
      ops.add(RotationOp.delete(slotName(i)));
    }
    if (occupied(i - 1)) {
      ops.add(RotationOp.rename(slotName(i - 1), slotName(i)));
    }
  }
  return ops;
}
