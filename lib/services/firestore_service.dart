import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/todo_model.dart';
import '../models/comment_model.dart';
import '../models/message_model.dart';
import '../models/deletion_record_model.dart';
import 'fcm_service.dart';
import 'log_service.dart';
import 'crypto_service.dart';
import 'auth_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Poke ──────────────────────────────────────────────────────────────────

  Future<void> sendPoke(String coupleId, String fromUid, String fromName) async {
    LogService.log('Sending poke from $fromName');
    await _db.doc('couples/$coupleId/pokes/status').set({
      'lastFrom': fromUid,
      'fromName': fromName,
      'sentAt': FieldValue.serverTimestamp(),
    });
    final partnerName = fromName == 'Ray' ? 'aproo' : 'ray';
    FcmService.send(
      partnerName: partnerName,
      title: '💕 $fromName poked you!',
      body: 'Open the app to poke back',
      type: 'poke',
    );
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> pokeStatusStream(String coupleId) {
    return _db.doc('couples/$coupleId/pokes/status').snapshots();
  }

  // ── To-do list ────────────────────────────────────────────────────────────

  Stream<List<TodoItem>> todoStream(String coupleId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TodoItem.fromMap(d.id, d.data())).toList());
  }

  Stream<TodoItem> todoDocStream(String coupleId, String todoId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .snapshots()
        .map((d) => TodoItem.fromMap(d.id, d.data() ?? {}));
  }

  Future<void> addTodo(String coupleId, TodoItem todo) async {
    LogService.log('Adding to-do: ${todo.title}');
    
    final titleEnc = await CryptoService().encryptString(todo.title);
    final detailsEnc = todo.details != null ? await CryptoService().encryptString(todo.details!) : null;
    final List<ChecklistItem> checklistEnc = [];
    for (final item in todo.checklist) {
      checklistEnc.add(item.copyWith(title: await CryptoService().encryptString(item.title)));
    }

    final encryptedTodo = TodoItem(
      id: todo.id,
      title: titleEnc,
      details: detailsEnc,
      isDone: todo.isDone,
      createdBy: todo.createdBy,
      createdAt: todo.createdAt,
      dueDate: todo.dueDate,
      assignedTo: todo.assignedTo,
      priority: todo.priority,
      completedAt: todo.completedAt,
      checklist: checklistEnc,
    );

    // 'updatedAt' is bookkeeping only, not part of TodoItem — the backup
    // pipeline's incremental delta queries (`where updatedAt > cursor`)
    // depend on every mutating write touching it, since createdAt alone
    // doesn't change on edits.
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .add({
      ...encryptedTodo.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final auth = AuthService();
    final senderName = auth.myName;
    final partnerName = auth.partnerName.toLowerCase();
    FcmService.send(
      partnerName: partnerName,
      title: '✅ New task added',
      body: '$senderName added a task',
      type: 'todo',
    );
  }

  Future<void> toggleTodo(String coupleId, TodoItem todo) async {
    final nextIsDone = !todo.isDone;
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todo.id)
        .update({
      'isDone': nextIsDone,
      'completedAt': nextIsDone ? DateTime.now().toIso8601String() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email != null) {
      final key = email == allowedEmails[0] ? 'ray' : 'aproo';
      await updatePresence(key);
    }
  }

  Future<void> updateTodoDetails(
      String coupleId, String todoId, String details) async {
    final detailsEnc = await CryptoService().encryptString(details);
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .update({
      'details': detailsEnc,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateTodoChecklist(
      String coupleId, String todoId, List<ChecklistItem> checklist) async {
    final List<ChecklistItem> checklistEnc = [];
    for (final item in checklist) {
      checklistEnc.add(item.copyWith(title: await CryptoService().encryptString(item.title)));
    }
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .update({
      'checklist': checklistEnc.map((item) => item.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateTodoMetadata(
      String coupleId, {
      required String todoId,
      String? priority,
      String? assignedTo,
      DateTime? dueDate,
      bool clearDueDate = false,
  }) async {
    final Map<String, dynamic> updates = {};
    updates['priority'] = priority;
    updates['assignedTo'] = assignedTo;
    if (clearDueDate) {
      updates['dueDate'] = null;
    } else if (dueDate != null) {
      updates['dueDate'] = dueDate.toIso8601String();
    }
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .update(updates);
  }

  Future<void> deleteTodo(String coupleId, String todoId) async {
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .delete();
    await _recordDeletion(coupleId, 'todos', todoId);
  }

  // ── Todo Comments ─────────────────────────────────────────────────────────

  Stream<List<TodoComment>> commentStream(String coupleId, String todoId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TodoComment.fromMap(d.id, d.data()))
            .toList());
  }

  Future<void> addComment(
      String coupleId, String todoId, TodoComment comment, String todoTitle) async {
    final textEnc = await CryptoService().encryptString(comment.text);
    final encryptedComment = TodoComment(
      id: comment.id,
      text: textEnc,
      authorName: comment.authorName,
      createdAt: comment.createdAt,
    );

    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .collection('comments')
        .add(encryptedComment.toMap());
    final partnerName = comment.authorName == 'Ray' ? 'aproo' : 'ray';
    FcmService.send(
      partnerName: partnerName,
      title: '🗨️ ${comment.authorName} commented',
      body: 'New note left on task',
      type: 'todo',
    );
  }

  Future<void> deleteComment(
      String coupleId, String todoId, String commentId) async {
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .collection('comments')
        .doc(commentId)
        .delete();
    await _recordDeletion(coupleId, 'todos/$todoId/comments', commentId);
  }

  // ── Chat ──────────────────────────────────────────────────────────────────

  Stream<List<Message>> messageStream(String coupleId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Message.fromMap(d.id, d.data())).toList());
  }

  /// One page of messages ordered newest-first.
  /// Returns the messages and a cursor for the next page.
  Future<({List<Message> messages, DocumentSnapshot? cursor})>
      fetchMessagePage(String coupleId, int limit,
          {DocumentSnapshot? startAfter}) async {
    Query<Map<String, dynamic>> q = _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snap = await q.get();
    final messages =
        snap.docs.map((d) => Message.fromMap(d.id, d.data())).toList();
    final cursor = snap.docs.isNotEmpty ? snap.docs.last : null;
    return (messages: messages, cursor: cursor);
  }

  /// All messages — used for full-history search.
  Future<List<Message>> getAllMessages(String coupleId) async {
    final snap = await _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .get();
    return snap.docs.map((d) => Message.fromMap(d.id, d.data())).toList();
  }

  Future<void> sendMessage(String coupleId, Message message,
      {String senderName = ''}) async {
    LogService.log('Sending message: ${message.text.substring(0, message.text.length > 20 ? 20 : message.text.length)}...');
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .add({
      ...message.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (senderName.isNotEmpty) {
      final partnerName = senderName == 'Ray' ? 'aproo' : 'ray';
      final String preview;
      if (message.text.startsWith('{"ciphertext":')) {
        preview = 'Sent a message';
      } else {
        preview = message.text.length > 60
            ? '${message.text.substring(0, 60)}…'
            : message.text;
      }
      FcmService.send(
        partnerName: partnerName,
        title: senderName,
        body: preview,
        type: 'chat',
      );
    }
  }

  Future<void> markMessagesRead(String coupleId, String myUid) async {
    final snap = await _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .where('senderId', isNotEqualTo: myUid)
        .get();

    final batch = _db.batch();
    for (final doc in snap.docs) {
      final readBy = List<String>.from(doc.data()['readBy'] as List? ?? []);
      if (!readBy.contains(myUid)) {
        batch.update(doc.reference, {
          'readBy': FieldValue.arrayUnion([myUid]),
          'readTimes.$myUid': DateTime.now().toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  Stream<int> unreadCountStream(String coupleId, String myUid) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .snapshots()
        .map((snap) => snap.docs.where((doc) {
              final data = doc.data();
              if (data['senderId'] == myUid) return false;
              final readBy =
                  List<String>.from(data['readBy'] as List? ?? []);
              return !readBy.contains(myUid);
            }).length);
  }

  Future<void> toggleReaction(
      String coupleId, String messageId, String emoji, String myUid) async {
    final ref = _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .doc(messageId);
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final rawReactions = Map<String, dynamic>.from(data['reactions'] ?? {});
    final uids =
        List<String>.from(rawReactions[emoji] ?? []);
    if (uids.contains(myUid)) {
      uids.remove(myUid);
    } else {
      uids.add(myUid);
    }
    if (uids.isEmpty) {
      rawReactions.remove(emoji);
    } else {
      rawReactions[emoji] = uids;
    }
    await ref.update({
      'reactions': rawReactions,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Presence / last seen ─────────────────────────────────────────────────

  Future<void> updatePresence(String myKey) async {
    LogService.log('Updating presence for $myKey');
    await _db.doc('couples/ray-aproo/status/presence').set({
      myKey: {
        'lastSeen': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  Future<void> registerPublicKey(String myKey, String publicKeyBase64) async {
    LogService.log('Registering E2EE public key for $myKey');
    await _db.doc('couples/ray-aproo/status/presence').set({
      myKey: {
        'publicKey': publicKeyBase64,
      }
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> presenceStream() {
    return _db.doc('couples/ray-aproo/status/presence').snapshots();
  }

  Future<void> updateMusicPresence(String myKey, Map<String, dynamic>? musicData) async {
    LogService.log('Updating music presence for $myKey: ${musicData?['track']}');
    await _db.doc('couples/ray-aproo/status/presence').set({
      myKey: {
        'music': musicData,
      }
    }, SetOptions(merge: true));
  }

  Future<void> updateBatteryPresence(String myKey, int batteryLevel, bool isCharging) async {
    LogService.log('Updating battery presence for $myKey: $batteryLevel% (charging: $isCharging)');
    await _db.doc('couples/ray-aproo/status/presence').set({
      myKey: {
        'battery': {
          'level': batteryLevel,
          'isCharging': isCharging,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      }
    }, SetOptions(merge: true));
  }

  // ── Sticky Notes ─────────────────────────────────────────────────────────

  Stream<QuerySnapshot<Map<String, dynamic>>> stickyNotesStream(String coupleId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('sticky_notes')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> addStickyNote(
      String coupleId, String text, String createdBy, String createdByName, int colorIndex) async {
    final encryptedText = await CryptoService().encryptString(text);
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('sticky_notes')
        .add({
      'text': encryptedText,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'colorIndex': colorIndex,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> archiveStickyNote(String coupleId, String noteId) async {
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('sticky_notes')
        .doc(noteId)
        .update({
      'isArchived': true,
      'archivedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> restoreStickyNote(String coupleId, String noteId) async {
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('sticky_notes')
        .doc(noteId)
        .update({
      'isArchived': false,
      'archivedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> permanentlyDeleteStickyNote(String coupleId, String noteId) async {
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('sticky_notes')
        .doc(noteId)
        .delete();
    await _recordDeletion(coupleId, 'sticky_notes', noteId);
  }

  // ── Deletion tombstones (for backup sync) ───────────────────────────────
  //
  // Cursor-based "what's new since X" queries never see deletions — a
  // removed doc simply stops appearing, it doesn't show up as a change. The
  // backup pipeline needs these tombstones to apply removals to the backup
  // copy without re-reading entire collections to diff them.

  Future<void> _recordDeletion(
      String coupleId, String collection, String docId) {
    return _db.collection('couples').doc(coupleId).collection('deletions').add({
      'collection': collection,
      'docId': docId,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<DeletionRecord>> deletionsSince(
      String coupleId, DateTime since) async {
    final snap = await _db
        .collection('couples')
        .doc(coupleId)
        .collection('deletions')
        .where('deletedAt', isGreaterThan: Timestamp.fromDate(since))
        .orderBy('deletedAt')
        .get();
    return snap.docs.map((d) => DeletionRecord.fromMap(d.data())).toList();
  }

  /// Tombstones only need to outlive the longest gap between successful
  /// backup runs. Call this after a backup run has confirmed it processed
  /// everything up to [before].
  Future<void> pruneDeletionsBefore(String coupleId, DateTime before) async {
    final snap = await _db
        .collection('couples')
        .doc(coupleId)
        .collection('deletions')
        .where('deletedAt', isLessThan: Timestamp.fromDate(before))
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ── Couple profile ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getCoupleProfile(String coupleId) async {
    final doc = await _db.collection('couples').doc(coupleId).get();
    return doc.data();
  }

  Future<void> updateCoupleProfile(
      String coupleId, Map<String, dynamic> data) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .set(data, SetOptions(merge: true));
  }

  // ── Snaps ─────────────────────────────────────────────────────────────────

  Stream<DocumentSnapshot<Map<String, dynamic>>> snapsStream(String coupleId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('snaps')
        .doc('current')
        .snapshots();
  }

  Future<void> sendSnap(String coupleId, String senderKey, String base64Photo, String caption) async {
    LogService.log('Sending new snap from $senderKey');
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('snaps')
        .doc('current')
        .set({
      '${senderKey}LatestPhoto': base64Photo,
      '${senderKey}Caption': caption,
      '${senderKey}SentAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Partner Info ─────────────────────────────────────────────────────────

  Stream<DocumentSnapshot<Map<String, dynamic>>> userDocStream(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  Future<void> updateProfile(String uid, Map<String, dynamic> profile) async {
    LogService.log('Updating partner profile for $uid');
    await _db.collection('users').doc(uid).set(
      {'profile': profile},
      SetOptions(merge: true),
    );
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> coupleDocStream(String coupleId) {
    return _db.collection('couples').doc(coupleId).snapshots();
  }

  Future<void> updateAnniversary(String coupleId, DateTime? anniversary) async {
    LogService.log('Updating couple anniversary');
    await _db.collection('couples').doc(coupleId).set(
      {
        'anniversary':
            anniversary != null ? Timestamp.fromDate(anniversary) : null,
      },
      SetOptions(merge: true),
    );
  }

  // ── Backup pipeline: bounded delta fetches ──────────────────────────────
  //
  // One-time `.get()` queries scoped by an "updated since" cursor, so the
  // backup pipeline only reads what's changed rather than re-reading whole
  // collections on every run. A null [since] means "everything" (first
  // backup ever, when there's no cursor yet).

  Query<Map<String, dynamic>> _sinceQuery(
      Query<Map<String, dynamic>> query, String field, DateTime? since) {
    if (since == null) return query;
    return query.where(field, isGreaterThan: Timestamp.fromDate(since));
  }

  Future<List<Map<String, dynamic>>> fetchTodosSince(
      String coupleId, DateTime? since) async {
    final query = _sinceQuery(
        _db.collection('couples').doc(coupleId).collection('todos'),
        'updatedAt',
        since);
    final snap = await query.get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Comments never get edited after creation (only deleted, which is
  /// covered by tombstones), so createdAt is a valid delta cursor for them
  /// without needing a separate updatedAt field.
  ///
  /// Uses a collectionGroup query to fetch across every todo's comments
  /// subcollection in one query rather than enumerating todo IDs first.
  /// Safe here because this Firebase project only ever has the one couple
  /// this app is built for — a collectionGroup query would need explicit
  /// per-couple filtering in a multi-tenant project.
  Future<List<Map<String, dynamic>>> fetchCommentsSince(
      DateTime? since) async {
    final query = _sinceQuery(
        _db.collectionGroup('comments'), 'createdAt', since);
    final snap = await query.get();
    return snap.docs
        .map((d) => {
              'id': d.id,
              'todoId': d.reference.parent.parent!.id,
              ...d.data(),
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchMessagesSince(
      String coupleId, DateTime? since) async {
    final query = _sinceQuery(
        _db.collection('couples').doc(coupleId).collection('messages'),
        'updatedAt',
        since);
    final snap = await query.get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<List<Map<String, dynamic>>> fetchStickyNotesSince(
      String coupleId, DateTime? since) async {
    final query = _sinceQuery(
        _db.collection('couples').doc(coupleId).collection('sticky_notes'),
        'updatedAt',
        since);
    final snap = await query.get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<Map<String, dynamic>?> fetchUserDoc(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data();
  }

  Future<Map<String, dynamic>?> fetchCoupleDoc(String coupleId) async {
    final snap = await _db.collection('couples').doc(coupleId).get();
    return snap.data();
  }

  // ── Backup pipeline: cheap integrity counts ─────────────────────────────
  //
  // Firestore's count() aggregation returns a collection's document count
  // for a flat, minimal cost — it does not read every doc — so this is
  // safe to use as a post-backup sanity check without reintroducing the
  // read-volume problem the backup pipeline exists to avoid.

  Future<int> countTodos(String coupleId) async {
    final agg = await _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .count()
        .get();
    return agg.count ?? 0;
  }

  Future<int> countMessages(String coupleId) async {
    final agg = await _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .count()
        .get();
    return agg.count ?? 0;
  }

  Future<int> countStickyNotes(String coupleId) async {
    final agg = await _db
        .collection('couples')
        .doc(coupleId)
        .collection('sticky_notes')
        .count()
        .get();
    return agg.count ?? 0;
  }
}
