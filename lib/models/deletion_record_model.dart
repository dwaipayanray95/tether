import 'package:cloud_firestore/cloud_firestore.dart';

/// A tombstone recording that a document was deleted, so the backup
/// pipeline can catch removals that a "what's new since cursor" query
/// would otherwise miss entirely.
class DeletionRecord {
  // Collection path relative to the couple doc, e.g. 'todos', 'sticky_notes',
  // or 'todos/{todoId}/comments' for nested collections.
  final String collection;
  final String docId;
  final DateTime deletedAt;

  const DeletionRecord({
    required this.collection,
    required this.docId,
    required this.deletedAt,
  });

  factory DeletionRecord.fromMap(Map<String, dynamic> map) {
    return DeletionRecord(
      collection: map['collection'] as String,
      docId: map['docId'] as String,
      deletedAt: (map['deletedAt'] as Timestamp).toDate(),
    );
  }
}
