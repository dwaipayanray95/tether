import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/todo_model.dart';
import '../models/comment_model.dart';
import '../models/message_model.dart';
import 'fcm_service.dart';
import 'log_service.dart';

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

  Future<void> addTodo(String coupleId, TodoItem todo) async {
    LogService.log('Adding to-do: ${todo.title}');
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .add(todo.toMap());
    final partnerName = todo.createdBy == 'Ray' ? 'aproo' : 'ray';
    FcmService.send(
      partnerName: partnerName,
      title: '✅ New task added',
      body: '${todo.createdBy}: ${todo.title}',
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
    });
    
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email != null) {
      final key = email == 'dwaipayanray95@gmail.com' ? 'ray' : 'aproo';
      await updatePresence(key);
    }
  }

  Future<void> updateTodoDetails(
      String coupleId, String todoId, String details) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .update({'details': details});
  }

  Future<void> deleteTodo(String coupleId, String todoId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .delete();
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
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .collection('comments')
        .add(comment.toMap());
    final partnerName = comment.authorName == 'Ray' ? 'aproo' : 'ray';
    FcmService.send(
      partnerName: partnerName,
      title: '🗨️ ${comment.authorName} commented',
      body: '${comment.text} · $todoTitle',
      type: 'comment',
    );
  }

  Future<void> deleteComment(
      String coupleId, String todoId, String commentId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .collection('comments')
        .doc(commentId)
        .delete();
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
        .add(message.toMap());
    if (senderName.isNotEmpty) {
      final partnerName = senderName == 'Ray' ? 'aproo' : 'ray';
      final preview = message.text.length > 60
          ? '${message.text.substring(0, 60)}…'
          : message.text;
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
    await ref.update({'reactions': rawReactions});
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
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('sticky_notes')
        .add({
      'text': text,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'colorIndex': colorIndex,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteStickyNote(String coupleId, String noteId) async {
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('sticky_notes')
        .doc(noteId)
        .delete();
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
}
