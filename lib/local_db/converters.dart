import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show Value;
import '../models/message_model.dart';
import '../models/todo_model.dart';
import '../models/comment_model.dart';
import 'app_database.dart';

/// Pure conversion functions between raw Firestore doc maps (as delivered by
/// a snapshot listener or the backup pipeline) and Drift row/companion
/// objects. Kept dependency-free of any live Firestore/Drive/crypto call —
/// only the `Timestamp` type is used, purely as a value type, same as
/// backup_merge.dart's sanitizeForJson() already does. Collection-agnostic
/// callers (LocalSyncService, LocalDbHydrationService) both funnel through
/// these, so there's exactly one place that knows how to turn a raw
/// Firestore doc into a local DB row per table.

/// Firestore stores messages' `sentAt` as an ISO-8601 string (not a native
/// Timestamp — see firestore_service.dart's sendMessage()), but `updatedAt`
/// and sticky notes' `createdAt`/`updatedAt` are real Timestamps written via
/// FieldValue.serverTimestamp(). This accepts either shape.
int? toEpochMillis(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate().toUtc().millisecondsSinceEpoch;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    return parsed?.toUtc().millisecondsSinceEpoch;
  }
  if (value is DateTime) return value.toUtc().millisecondsSinceEpoch;
  return null;
}

/// Latest value of [field] across raw (pre-sanitized) Firestore docs —
/// unlike backup_merge.dart's maxTimestampField() (which only handles
/// already-sanitized ISO strings), this accepts the mixed Timestamp/String
/// shape a fresh Firestore fetch actually has, via toEpochMillis(). Used by
/// LocalSyncService to advance its own backfill cursor to the newest
/// message actually observed in a fetch, rather than the device clock —
/// same clock-skew-avoidance reasoning the backup pipeline's cursor uses.
DateTime? maxRawTimestampField(List<Map<String, dynamic>> docs, String field) {
  int? latest;
  for (final doc in docs) {
    final millis = toEpochMillis(doc[field]);
    if (millis == null) continue;
    if (latest == null || millis > latest) latest = millis;
  }
  return latest == null ? null : DateTime.fromMillisecondsSinceEpoch(latest, isUtc: true);
}

MessagesCompanion messageRowFromFirestoreMap(
  String id,
  Map<String, dynamic> data, {
  String deliveryStatus = 'sent',
}) {
  return MessagesCompanion.insert(
    id: id,
    senderId: data['senderId'] as String? ?? '',
    textContent: data['text'] as String? ?? '',
    type: data['type'] as String? ?? 'text',
    imageUrl: Value(data['imageUrl'] as String?),
    audioUrl: Value(data['audioUrl'] as String?),
    duration: Value(data['duration'] as int?),
    sentAt: toEpochMillis(data['sentAt']) ?? 0,
    readBy: Value(_encodeList(data['readBy'])),
    readTimes: Value(_encodeMap(data['readTimes'])),
    replyToId: Value(data['replyToId'] as String?),
    replyToText: Value(data['replyToText'] as String?),
    reactions: Value(_encodeMap(data['reactions'])),
    updatedAt: toEpochMillis(data['updatedAt']) ?? toEpochMillis(data['sentAt']) ?? 0,
    deliveryStatus: Value(deliveryStatus),
  );
}

/// Builds the optimistic local-DB row for a message the user is sending
/// right now, before any Firestore round trip — this is the one exception
/// to "writes always go through the Firestore listener echo" (see
/// AGENTS.md's message delivery status design): a message doesn't exist
/// anywhere yet at the instant of sending, so something has to render it
/// immediately, including while offline.
MessagesCompanion messageRowFromModel(
  Message message, {
  required String deliveryStatus,
}) {
  return MessagesCompanion.insert(
    id: message.id,
    senderId: message.senderId,
    textContent: message.text,
    type: message.type.name,
    imageUrl: Value(message.imageUrl),
    audioUrl: Value(message.audioUrl),
    duration: Value(message.duration),
    sentAt: message.sentAt.toUtc().millisecondsSinceEpoch,
    readBy: Value(jsonEncode(message.readBy)),
    readTimes: Value(message.readTimes.isEmpty
        ? null
        : jsonEncode(message.readTimes
            .map((k, v) => MapEntry(k, v.toIso8601String())))),
    replyToId: Value(message.replyToId),
    replyToText: Value(message.replyToText),
    reactions: Value(message.reactions.isEmpty ? null : jsonEncode(message.reactions)),
    updatedAt: message.sentAt.toUtc().millisecondsSinceEpoch,
    deliveryStatus: Value(deliveryStatus),
  );
}

/// jsonDecode()'s static return type is `dynamic`, and depending on Dart/
/// platform internals the actual runtime Map it hands back is not always
/// exactly `Map&lt;String, dynamic&gt;` at the type-check level — a plain
/// `as Map&lt;String, dynamic&gt;` cast on it can throw
/// "_Map&lt;dynamic, dynamic&gt; is not a subtype of Map&lt;String, dynamic&gt;"
/// even though every key genuinely is a String. Re-wrapping via
/// `Map<String, dynamic>.from(...)` builds a map with the correct static
/// type regardless of the source map's exact generic parameters, so this
/// can never throw that specific cast error again.
Map<String, dynamic> _decodeJsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) return {};
  return Map<String, dynamic>.from(decoded);
}

List<dynamic> _decodeJsonArray(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List) return [];
  return List<dynamic>.from(decoded);
}

/// Builds the Firestore-delta-shaped map for a message row — ISO-8601
/// string dates, decoded (not re-encoded) reactions/readTimes/readBy, an
/// 'id' key — i.e. exactly what firestore_service.dart's
/// fetchMessagesSince() would have produced, so backup_service.dart's
/// pure merge functions (mergeDelta, sanitizeForJson, etc.) work
/// unchanged regardless of whether the data came from Firestore directly
/// or from here (see BackupService's Phase 4 data-source switch).
///
/// Includes the same bare-{} type-safety note as messageFromRow below —
/// this is the ONE place that literal exists now, both callers share it.
Map<String, dynamic> messageMapFromRow(MessageRow row) {
  return {
    'id': row.id,
    'senderId': row.senderId,
    'text': row.textContent,
    'type': row.type,
    'imageUrl': row.imageUrl,
    'audioUrl': row.audioUrl,
    'duration': row.duration,
    'sentAt': DateTime.fromMillisecondsSinceEpoch(row.sentAt, isUtc: true)
        .toIso8601String(),
    'updatedAt': DateTime.fromMillisecondsSinceEpoch(row.updatedAt, isUtc: true)
        .toIso8601String(),
    'readBy': _decodeJsonArray(row.readBy),
    // Bare {} here would be an untyped Dart map literal — defaults to
    // Map<dynamic, dynamic> at runtime, not Map<String, dynamic>, which is
    // exactly what caused the real production bug this converter's tests
    // now guard against (an `as Map<String, dynamic>?` cast on it throws).
    'readTimes': row.readTimes == null
        ? <String, dynamic>{}
        : _decodeJsonObject(row.readTimes!),
    'replyToId': row.replyToId,
    'replyToText': row.replyToText,
    'reactions': row.reactions == null
        ? <String, dynamic>{}
        : _decodeJsonObject(row.reactions!),
  };
}

/// Converts a local DB row back into the app's Message model — the shape
/// chat_screen.dart's existing rendering code (_MessageBubble, decryption
/// cache, etc.) already expects, unchanged by the local-DB cutover.
Message messageFromRow(MessageRow row) => Message.fromMap(row.id, messageMapFromRow(row));

TodosCompanion todoRowFromFirestoreMap(String id, Map<String, dynamic> data) {
  return TodosCompanion.insert(
    id: id,
    title: data['title'] as String? ?? '',
    details: Value(data['details'] as String?),
    isDone: Value(data['isDone'] as bool? ?? false),
    createdBy: data['createdBy'] as String? ?? '',
    createdAt: toEpochMillis(data['createdAt']) ?? 0,
    dueDate: Value(toEpochMillis(data['dueDate'])),
    assignedTo: Value(data['assignedTo'] as String?),
    priority: Value(data['priority'] as String?),
    completedAt: Value(toEpochMillis(data['completedAt'])),
    checklist: Value(_encodeList(data['checklist'])),
    updatedAt: toEpochMillis(data['updatedAt']) ?? toEpochMillis(data['createdAt']) ?? 0,
  );
}

TodoCommentsCompanion commentRowFromFirestoreMap(
    String id, String todoId, Map<String, dynamic> data) {
  return TodoCommentsCompanion.insert(
    id: id,
    todoId: todoId,
    textContent: data['text'] as String? ?? '',
    authorName: data['authorName'] as String? ?? '',
    createdAt: toEpochMillis(data['createdAt']) ?? 0,
  );
}

StickyNotesCompanion stickyNoteRowFromFirestoreMap(
    String id, Map<String, dynamic> data) {
  return StickyNotesCompanion.insert(
    id: id,
    textContent: data['text'] as String? ?? '',
    createdBy: data['createdBy'] as String? ?? '',
    createdByName: data['createdByName'] as String? ?? '',
    colorIndex: data['colorIndex'] as int? ?? 0,
    createdAt: toEpochMillis(data['createdAt']) ?? 0,
    updatedAt: toEpochMillis(data['updatedAt']) ?? toEpochMillis(data['createdAt']) ?? 0,
    isArchived: Value(data['isArchived'] as bool? ?? false),
    archivedAt: Value(toEpochMillis(data['archivedAt'])),
  );
}

/// Firestore-delta-shaped map for a sticky note row. There's no dedicated
/// StickyNote app model (sticky_board.dart reads the Drift row directly),
/// so this exists purely for the backup pipeline's data-source switch.
Map<String, dynamic> stickyNoteMapFromRow(StickyNote row) {
  return {
    'id': row.id,
    'text': row.textContent,
    'createdBy': row.createdBy,
    'createdByName': row.createdByName,
    'colorIndex': row.colorIndex,
    'createdAt': DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true)
        .toIso8601String(),
    'updatedAt': DateTime.fromMillisecondsSinceEpoch(row.updatedAt, isUtc: true)
        .toIso8601String(),
    'isArchived': row.isArchived,
    'archivedAt': row.archivedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.archivedAt!, isUtc: true).toIso8601String(),
  };
}

String _encodeList(dynamic value) => jsonEncode(value ?? []);

String? _encodeMap(dynamic value) => value == null ? null : jsonEncode(value);

/// Firestore-delta-shaped map for a todo row — see messageMapFromRow's doc
/// comment for why this shape (ISO strings, 'id' key) matters for the
/// backup pipeline.
Map<String, dynamic> todoMapFromRow(Todo row) {
  return {
    'id': row.id,
    'title': row.title,
    'details': row.details,
    'isDone': row.isDone,
    'createdBy': row.createdBy,
    'createdAt': DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true)
        .toIso8601String(),
    'updatedAt': DateTime.fromMillisecondsSinceEpoch(row.updatedAt, isUtc: true)
        .toIso8601String(),
    'dueDate': row.dueDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.dueDate!, isUtc: true).toIso8601String(),
    'assignedTo': row.assignedTo,
    'priority': row.priority,
    'completedAt': row.completedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.completedAt!, isUtc: true).toIso8601String(),
    'checklist': _decodeJsonArray(row.checklist),
  };
}

/// Converts a local DB row back into the app's TodoItem model — same
/// shape todo_screen.dart's existing rendering/notification-scheduling
/// code already expects. TodoItem.fromMap() already defensively converts
/// checklist items via `Map<String, dynamic>.from(item as Map)`, so no
/// extra safety net is needed here the way messageFromRow needed one.
TodoItem todoFromRow(Todo row) => TodoItem.fromMap(row.id, todoMapFromRow(row));

/// Firestore-delta-shaped map for a comment row — includes 'todoId',
/// matching fetchCommentsSince()'s shape (comments come from a
/// collectionGroup query, so the parent todo id has to travel alongside).
Map<String, dynamic> commentMapFromRow(TodoCommentRow row) {
  return {
    'id': row.id,
    'todoId': row.todoId,
    'text': row.textContent,
    'authorName': row.authorName,
    'createdAt': DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true)
        .toIso8601String(),
  };
}

TodoComment commentFromRow(TodoCommentRow row) =>
    TodoComment.fromMap(row.id, commentMapFromRow(row));
