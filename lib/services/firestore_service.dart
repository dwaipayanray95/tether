import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/todo_model.dart';
import '../models/comment_model.dart';
import '../models/message_model.dart';
import 'fcm_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Poke ──────────────────────────────────────────────────────────────────

  Future<void> sendPoke(String coupleId, String fromUid, String fromName) async {
    await _db.doc('couples/$coupleId/pokes/status').set({
      'lastFrom': fromUid,
      'fromName': fromName,
      'sentAt': FieldValue.serverTimestamp(),
    });
    final partnerName = fromName == 'Raayyy' ? 'aproo' : 'raayyy';
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
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .add(todo.toMap());
    final partnerName = todo.createdBy == 'Raayyy' ? 'aproo' : 'raayyy';
    FcmService.send(
      partnerName: partnerName,
      title: '✅ New task added',
      body: '${todo.createdBy}: ${todo.title}',
      type: 'todo',
    );
  }

  Future<void> toggleTodo(String coupleId, TodoItem todo) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todo.id)
        .update({'isDone': !todo.isDone});
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
    final partnerName = comment.authorName == 'Raayyy' ? 'aproo' : 'raayyy';
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

  Future<void> sendMessage(String coupleId, Message message,
      {String senderName = ''}) async {
    await _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .add(message.toMap());
    if (senderName.isNotEmpty) {
      final partnerName = senderName == 'Raayyy' ? 'aproo' : 'raayyy';
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

  Future<void> updatePresence(String myKey, {bool isOnline = true}) async {
    await _db.doc('couples/raayyy-aproo/presence/$myKey').set({
      'lastSeen': FieldValue.serverTimestamp(),
      'isOnline': isOnline,
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> presenceStream(String key) {
    return _db
        .doc('couples/raayyy-aproo/presence/$key')
        .snapshots();
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
