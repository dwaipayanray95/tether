import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'fcm_service.dart';
import 'log_service.dart';

/// Firestore signalling paths under couples/ray-aproo/calls/{callId}:
///   status:      'ringing' | 'active' | 'ended'
///   callerName:  String
///   createdAt:   Timestamp

class CallService {
  static final _db = FirebaseFirestore.instance;
  static const _coupleDoc = 'couples/ray-aproo';

  // ── Outgoing call ─────────────────────────────────────────────────────────

  /// Creates a call document and sends an FCM ring.
  /// Returns the callId.
  static Future<String> startCall({
    required String callerName,
  }) async {
    LogService.log('Starting outgoing call: $callerName');
    final ref = _db
        .collection('$_coupleDoc/calls')
        .doc();
    final callId = ref.id;

    await ref.set({
      'callerName': callerName,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Notify partner
    final partnerName = callerName == 'Ray' ? 'aproo' : 'ray';
    FcmService.send(
      partnerName: partnerName,
      title: '📞 $callerName is calling…',
      body: 'Tap to answer',
      type: 'call',
      extra: {'callId': callId},
    );

    return callId;
  }

  // ── Incoming call ─────────────────────────────────────────────────────────

  /// Marks a call as accepted (active).
  static Future<void> acceptCall(String callId) async {
    LogService.log('Accepting call: $callId');
    final ref = _db.doc('$_coupleDoc/calls/$callId');
    await ref.update({
      'status': 'active',
    });
  }

  // ── End call ──────────────────────────────────────────────────────────────

  static Future<void> endCall(String callId) async {
    LogService.log('Ending call: $callId');
    try {
      await _db
          .doc('$_coupleDoc/calls/$callId')
          .set({'status': 'ended'}, SetOptions(merge: true));
    } catch (e) {
      LogService.log('Error ending call (ignored): $e');
    }
  }

  /// Stream of the call's status field.
  static Stream<String?> callStatusStream(String callId) {
    return _db
        .doc('$_coupleDoc/calls/$callId')
        .snapshots()
        .map((snap) => snap.data()?['status'] as String?);
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> getCall(
      String callId) {
    return _db.doc('$_coupleDoc/calls/$callId').get();
  }

  // ── Incoming call stream ─────────────────────────────────────────────────

  /// Stream of the latest ringing call document.
  static Stream<DocumentSnapshot<Map<String, dynamic>>?> incomingCallStream(
      String myName) {
    return _db
        .collection('$_coupleDoc/calls')
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snap) {
      for (final doc in snap.docs) {
        if (doc.data()['callerName'] != myName) {
          return doc;
        }
      }
      return null;
    });
  }
}
