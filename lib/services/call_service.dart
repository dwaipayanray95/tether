import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'fcm_service.dart';

/// Firestore signalling paths under couples/ray-aproo/calls/{callId}:
///   offer:       {sdp, type}
///   answer:      {sdp, type}
///   status:      'ringing' | 'active' | 'ended'
///   callerName:  String
///   calleeCandidates/  subcollection
///   callerCandidates/  subcollection

class CallService {
  static final _db = FirebaseFirestore.instance;
  static const _coupleDoc = 'couples/ray-aproo';

  // ── Outgoing call ─────────────────────────────────────────────────────────

  /// Creates a call document, writes the offer, and sends an FCM ring.
  /// Returns the callId.
  static Future<String> startCall({
    required String callerName,
    required RTCSessionDescription offer,
    required void Function(RTCSessionDescription answer) onAnswer,
    required void Function(RTCIceCandidate) onRemoteCandidate,
  }) async {
    final ref = _db
        .collection('$_coupleDoc/calls')
        .doc();
    final callId = ref.id;

    await ref.set({
      'callerName': callerName,
      'status': 'ringing',
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Listen for the answer
    StreamSubscription? answerSub;
    answerSub = ref.snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) return;
      if (data['answer'] != null && data['status'] == 'active') {
        final a = Map<String, dynamic>.from(data['answer']);
        onAnswer(RTCSessionDescription(a['sdp'], a['type']));
        answerSub?.cancel();
      }
    });

    // Listen for callee ICE candidates
    ref.collection('calleeCandidates').snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data()!;
          onRemoteCandidate(RTCIceCandidate(
            d['candidate'],
            d['sdpMid'],
            d['sdpMLineIndex'],
          ));
        }
      }
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

  /// Writes a caller ICE candidate to Firestore.
  static Future<void> sendCallerCandidate(
      String callId, RTCIceCandidate c) async {
    await _db
        .collection('$_coupleDoc/calls/$callId/callerCandidates')
        .add({
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    });
  }

  // ── Incoming call ─────────────────────────────────────────────────────────

  /// Answers a call: writes the answer SDP and marks status 'active'.
  static Future<void> answerCall({
    required String callId,
    required RTCSessionDescription answer,
    required void Function(RTCIceCandidate) onRemoteCandidate,
  }) async {
    final ref = _db.doc('$_coupleDoc/calls/$callId');
    await ref.update({
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'status': 'active',
    });

    // Listen for caller ICE candidates
    ref.collection('callerCandidates').snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data()!;
          onRemoteCandidate(RTCIceCandidate(
            d['candidate'],
            d['sdpMid'],
            d['sdpMLineIndex'],
          ));
        }
      }
    });
  }

  /// Writes a callee ICE candidate to Firestore.
  static Future<void> sendCalleeCandidate(
      String callId, RTCIceCandidate c) async {
    await _db
        .collection('$_coupleDoc/calls/$callId/calleeCandidates')
        .add({
      'candidate': c.candidate,
      'sdpMid': c.sdpMid,
      'sdpMLineIndex': c.sdpMLineIndex,
    });
  }

  // ── End call ──────────────────────────────────────────────────────────────

  static Future<void> endCall(String callId) async {
    await _db
        .doc('$_coupleDoc/calls/$callId')
        .update({'status': 'ended'});
  }

  // ── Incoming call stream ─────────────────────────────────────────────────

  /// Stream of the latest ringing call document (null when no active ring).
  static Stream<DocumentSnapshot<Map<String, dynamic>>?> incomingCallStream(
      String myName) {
    // Watch the 2 most recent calls; show the one that's still ringing
    return _db
        .collection('$_coupleDoc/calls')
        .orderBy('createdAt', descending: true)
        .limit(2)
        .snapshots()
        .map((snap) {
      for (final doc in snap.docs) {
        final data = doc.data();
        // It's incoming if callerName != me and status == ringing
        if (data['callerName'] != myName && data['status'] == 'ringing') {
          return doc;
        }
      }
      return null;
    });
  }
}
