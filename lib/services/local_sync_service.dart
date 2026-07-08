import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../local_db/app_database.dart';
import '../local_db/converters.dart';
import '../local_db/daos/message_dao.dart';
import '../local_db/daos/todo_dao.dart';
import '../local_db/daos/comment_dao.dart';
import '../local_db/daos/sticky_note_dao.dart';
import 'firestore_service.dart';
import 'local_sync_cursor_store.dart';
import 'log_service.dart';

/// Keeps the local DB (see AGENTS.md "Local-First Architecture") current by
/// listening to Firestore the same way the screens do today, and writing
/// results into Drift instead of directly into widget state. Firestore
/// remains the single source of truth for real-time delivery between the
/// two partners' devices — this service only mirrors it locally; it never
/// writes back to Firestore itself (screens' existing send/edit/delete
/// calls to FirestoreService are unchanged and untouched by this class).
///
/// chat_screen.dart / todo_screen.dart / sticky_board.dart all read from
/// the local DB this service maintains — see AGENTS.md's Phase 0-4 notes.
class LocalSyncService {
  final AppDatabase _appDb = AppDatabase.instance();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();
  final LocalSyncCursorStore _cursorStore = LocalSyncCursorStore();

  late final MessageDao messageDao = MessageDao(_appDb);
  late final TodoDao todoDao = TodoDao(_appDb);
  late final CommentDao commentDao = CommentDao(_appDb);
  late final StickyNoteDao stickyNoteDao = StickyNoteDao(_appDb);

  StreamSubscription? _messagesSub;
  StreamSubscription? _todosSub;
  StreamSubscription? _stickyNotesSub;
  StreamSubscription? _commentsSub;

  bool _started = false;

  /// Starts (or is a no-op if already started) all live listeners, plus a
  /// one-time full-history backfill for messages (the only collection
  /// whose live listener is windowed — todos/sticky-notes/comments have no
  /// `.limit` today, so their live listeners already deliver full history).
  Future<void> startAll(String coupleId) async {
    if (_started) return;
    _started = true;

    _watchMessages(coupleId);
    _watchTodos(coupleId);
    _watchStickyNotes(coupleId);
    _watchAllComments(coupleId);

    // Fire-and-forget: older messages rarely change, no need to block
    // startup on this completing.
    unawaited(_backfillFullMessageHistory(coupleId));
  }

  Future<void> stopAll() async {
    await _messagesSub?.cancel();
    await _todosSub?.cancel();
    await _stickyNotesSub?.cancel();
    await _commentsSub?.cancel();
    _started = false;
  }

  void _watchMessages(String coupleId) {
    _messagesSub?.cancel();
    final query = _firestore
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(50);

    final myUid = FirebaseAuth.instance.currentUser?.uid;

    _messagesSub = query.snapshots().listen((snapshot) async {
      final upserts = <MessagesCompanion>[];
      for (final change in snapshot.docChanges) {
        // Do NOT treat `removed` as a deletion here. This query is windowed
        // (`.limit(50)`), so a `removed` doc-change almost always means the
        // doc fell out of the top-50 window because a newer message pushed
        // it out — it still exists in Firestore. There is also no
        // deleteMessage() anywhere in this app (messages are never actually
        // deletable), so a `removed` event on this listener can never be a
        // real deletion. Treating it as one used to silently erase one real
        // message from the local DB every time a new message was sent,
        // permanently — the incremental backfill cursor made this worse by
        // never re-fetching messages older than the last sync point to
        // self-heal it. (Todos/sticky notes/comments below have no `.limit`
        // on their queries, so `removed` there is unambiguous and correctly
        // still means a real delete.)
        if (change.type == DocumentChangeType.removed) continue;
        final data = change.doc.data();
        if (data == null) continue;

        final delivered = data['deliveredAt'] != null;
        final status = delivered
            ? 'delivered'
            : (change.doc.metadata.hasPendingWrites ? 'pending' : 'sent');
        upserts.add(
            messageRowFromFirestoreMap(change.doc.id, data, deliveryStatus: status));

        // This device is the recipient of a message it just first saw —
        // write back a delivery receipt so the SENDER's device can show
        // "delivered" without the recipient needing to open the chat.
        // Guarded by !hasPendingWrites so this only fires once the message
        // has actually round-tripped through the server (an
        // optimistic/pending local echo isn't a real delivery yet).
        if (change.type == DocumentChangeType.added &&
            myUid != null &&
            data['senderId'] != myUid &&
            !delivered &&
            !change.doc.metadata.hasPendingWrites) {
          unawaited(_firestoreService
              .markMessageDelivered(coupleId, change.doc.id)
              .catchError((e) =>
                  LogService.log('LocalSyncService: markMessageDelivered failed: $e')));
        }
      }
      if (upserts.isNotEmpty) await messageDao.upsertBatch(upserts);
    }, onError: (e) {
      LogService.log('LocalSyncService: messages listener error: $e');
    });
  }

  /// Incremental after the first run — a persisted cursor (the newest
  /// `updatedAt` actually backfilled) means every launch after the very
  /// first one only fetches what's changed since last time, instead of
  /// re-reading the entire message history from Firestore on every single
  /// app open. That full re-read was a real, unnecessary cost on every
  /// launch (not just fresh installs) — the local DB already has
  /// everything from last time, so most of that Firestore read was just
  /// being upserted right back over data already there.
  Future<void> _backfillFullMessageHistory(String coupleId) async {
    try {
      final cursor = await _cursorStore.loadMessagesCursor();
      final all = await _firestoreService.fetchMessagesSince(coupleId, cursor);
      final rows = all
          .map((doc) => messageRowFromFirestoreMap(
              doc['id'] as String, doc, deliveryStatus: 'sent'))
          .toList();
      await messageDao.upsertBatch(rows);

      final newCursor = maxRawTimestampField(all, 'updatedAt') ?? cursor;
      if (newCursor != null) {
        await _cursorStore.saveMessagesCursor(newCursor);
      }

      LogService.log(
          'LocalSyncService: backfilled ${rows.length} message(s) into local DB (since: ${cursor ?? "beginning"})');
    } catch (e) {
      LogService.log('LocalSyncService: message backfill failed: $e');
    }
  }

  void _watchTodos(String coupleId) {
    _todosSub?.cancel();
    final query =
        _firestore.collection('couples').doc(coupleId).collection('todos');

    _todosSub = query.snapshots().listen((snapshot) async {
      final upserts = <TodosCompanion>[];
      final deletedIds = <String>[];
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          deletedIds.add(change.doc.id);
          continue;
        }
        final data = change.doc.data();
        if (data == null) continue;
        upserts.add(todoRowFromFirestoreMap(change.doc.id, data));
      }
      if (upserts.isNotEmpty) await todoDao.upsertBatch(upserts);
      for (final id in deletedIds) {
        await todoDao.deleteById(id);
      }
    }, onError: (e) {
      LogService.log('LocalSyncService: todos listener error: $e');
    });
  }

  void _watchStickyNotes(String coupleId) {
    _stickyNotesSub?.cancel();
    final query = _firestore
        .collection('couples')
        .doc(coupleId)
        .collection('sticky_notes');

    _stickyNotesSub = query.snapshots().listen((snapshot) async {
      final upserts = <StickyNotesCompanion>[];
      final deletedIds = <String>[];
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          deletedIds.add(change.doc.id);
          continue;
        }
        final data = change.doc.data();
        if (data == null) continue;
        upserts.add(stickyNoteRowFromFirestoreMap(change.doc.id, data));
      }
      if (upserts.isNotEmpty) await stickyNoteDao.upsertBatch(upserts);
      for (final id in deletedIds) {
        await stickyNoteDao.deleteById(id);
      }
    }, onError: (e) {
      LogService.log('LocalSyncService: sticky notes listener error: $e');
    });
  }

  /// Uses a collectionGroup listener across every todo's comments
  /// subcollection — same approach firestore_service.dart's
  /// fetchCommentsSince() already uses for the backup pipeline (safe here
  /// because this Firebase project only ever has the one couple this app
  /// is built for). No `.limit`, so this alone delivers full comment
  /// history, no separate backfill needed.
  void _watchAllComments(String coupleId) {
    _commentsSub?.cancel();
    final query = _firestore.collectionGroup('comments');

    _commentsSub = query.snapshots().listen((snapshot) async {
      final upserts = <TodoCommentsCompanion>[];
      final deletedIds = <String>[];
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          deletedIds.add(change.doc.id);
          continue;
        }
        final data = change.doc.data();
        if (data == null) continue;
        final todoId = change.doc.reference.parent.parent?.id;
        if (todoId == null) continue;
        upserts.add(commentRowFromFirestoreMap(change.doc.id, todoId, data));
      }
      if (upserts.isNotEmpty) await commentDao.upsertBatch(upserts);
      for (final id in deletedIds) {
        await commentDao.deleteById(id);
      }
    }, onError: (e) {
      LogService.log('LocalSyncService: comments listener error: $e');
    });
  }
}
