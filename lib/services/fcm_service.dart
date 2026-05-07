import 'package:cloud_firestore/cloud_firestore.dart';
import 'call_handler_service.dart';

class FcmService {
  static Future<String?> _getPartnerUid(String partnerName) async {
    final partnerEmail = partnerName.toLowerCase() == 'ray' 
        ? 'ray@redacted.invalid' 
        : 'aproo@redacted.invalid';
    
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: partnerEmail)
        .limit(1)
        .get();
    
    if (snap.docs.isNotEmpty) return snap.docs.first.id;
    return null;
  }

  static Future<void> send({
    required String partnerName,
    required String title,
    required String body,
    String type = 'general',
    Map<String, String>? extra,
  }) async {
    try {
      final partnerUid = await _getPartnerUid(partnerName);
      if (partnerUid == null) return;

      CallHandlerService().signalingService?.sendNotification(
        partnerUid,
        title,
        body,
        payload: {'type': type, ...?extra},
      );
    } catch (_) {}
  }
}
