import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/todo_model.dart';
import '../models/comment_model.dart';
import '../models/message_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Poke ──────────────────────────────────────────────────────────────────

  Future<void> sendPoke(String fromUid, String toUid, String fromName) async {
    await _db.collection('pokes').add({
      'from': fromUid,
      'to': toUid,
      'fromName': fromName,
      'sentAt': DateTime.now().toIso8601String(),
    });
  }

  Stream<QuerySnapshot> pokeStream(String toUid) {
    return _db
        .collection('pokes')
        .where('to', isEqualTo: toUid)
        .orderBy('sentAt', descending: true)
        .limit(1)
        .snapshots();
  }

  // ── To-do list ────────────────────────────────────────────────────────────

  Stream<List<TodoItem>> todoStream(String coupleId) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TodoItem.fromMap(d.id, d.data()))
            .toList());
  }

  Future<void> addTodo(String coupleId, TodoItem todo) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .add(todo.toMap());
  }

  Future<void> toggleTodo(String coupleId, TodoItem todo) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todo.id)
        .update({'isDone': !todo.isDone});
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
      String coupleId, String todoId, TodoComment comment) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('todos')
        .doc(todoId)
        .collection('comments')
        .add(comment.toMap());
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

  Future<void> sendMessage(String coupleId, Message message) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection('messages')
        .add(message.toMap());
  }

  // ── Couple profile ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getCoupleProfile(String coupleId) async {
    final doc = await _db.collection('couples').doc(coupleId).get();
    return doc.data();
  }

  Future<void> updateCoupleProfile(
      String coupleId, Map<String, dynamic> data) {
    return _db.collection('couples').doc(coupleId).set(data, SetOptions(merge: true));
  }
}
