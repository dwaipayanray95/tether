import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/fcm_service.dart';
import '../../theme/app_theme.dart';

class QuickSnap extends StatefulWidget {
  const QuickSnap({super.key});

  @override
  State<QuickSnap> createState() => _QuickSnapState();
}

class _QuickSnapState extends State<QuickSnap> {
  final _auth = AuthService();
  final _firestore = FirestoreService();
  final _picker = ImagePicker();
  
  bool _isUploading = false;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _firestore.snapsStream(coupleId);
  }

  // ── Snap picking and upload ────────────────────────────────────────────────

  Future<void> _pickAndSendSnap(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 70,
      );

      if (pickedFile == null) return;

      setState(() => _isUploading = true);
      HapticFeedback.mediumImpact();

      final bytes = await File(pickedFile.path).readAsBytes();
      final base64String = base64Encode(bytes);

      final myKey = _auth.myName.toLowerCase(); // 'ray' or 'aproo'
      await _firestore.sendSnap(coupleId, myKey, base64String);

      // Trigger high priority FCM push notification to partner
      final partnerName = _auth.partnerName.toLowerCase();
      await FcmService.send(
        partnerName: partnerName,
        title: '📷 New Quick Snap!',
        body: '${_auth.myDisplayName} sent you a live photo. Open Tether to view!',
        type: 'snap',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Snap sent successfully! 📸'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload snap: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showImageSourceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send a Quick Snap',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSendSnap(ImageSource.camera);
                    },
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              color: AppTheme.primary, size: 28),
                        ),
                        const SizedBox(height: 8),
                        Text('Camera',
                            style: GoogleFonts.dmSans(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSendSnap(ImageSource.gallery);
                    },
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.photo_library_rounded,
                              color: AppTheme.primary, size: 28),
                        ),
                        const SizedBox(height: 8),
                        Text('Gallery',
                            style: GoogleFonts.dmSans(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Immersive Full-Screen Viewer ───────────────────────────────────────────

  void _showFullScreenViewer(Uint8List imageBytes, String title) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.95),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(ctx),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white, size: 26),
              onPressed: () async {
                HapticFeedback.lightImpact();
                try {
                  final tempDir = await getTemporaryDirectory();
                  final file = File('${tempDir.path}/tether_snap_${DateTime.now().millisecondsSinceEpoch}.jpg');
                  await file.writeAsBytes(imageBytes);

                  // Open the file inside the system viewer so the user can easily save it or share it
                  final result = await OpenFile.open(file.path);
                  if (result.type != ResultType.done && ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Could not open file: ${result.message}'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Error saving snap: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 3.5,
            child: Image.memory(
              imageBytes,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final partnerName = _auth.partnerDisplayName;
    final partnerKey = _auth.partnerName.toLowerCase();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
            ),
            child: Center(
              child: Text(
                'Error loading snap: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          );
        }

        final data = snapshot.data?.data();
        final partnerSnapBase64 = data?['${partnerKey}LatestBase64'] as String?;
        final partnerSentAt = data?['${partnerKey}SentAt'] as Timestamp?;

        Uint8List? partnerImageBytes;
        if (partnerSnapBase64 != null) {
          try {
            partnerImageBytes = base64Decode(partnerSnapBase64);
          } catch (_) {}
        }

        return Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1716), Color(0xFF261D1C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFE8715A).withValues(alpha: 0.15),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE8715A).withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              children: [
                // Display Partner Snap Image
                if (partnerImageBytes != null)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => _showFullScreenViewer(
                        partnerImageBytes!,
                        'Snap from $partnerName',
                      ),
                      child: Image.memory(
                        partnerImageBytes,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else
                  Positioned.fill(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.photo_outlined,
                              color: Colors.white24, size: 40),
                          const SizedBox(height: 8),
                          Text(
                            'No snaps from $partnerName yet',
                            style: GoogleFonts.dmSans(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Top Info Overlay (Timestamp)
                if (partnerImageBytes != null && partnerSentAt != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_rounded,
                              color: Colors.white70, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            '$partnerName sent ${timeago.format(partnerSentAt.toDate(), locale: 'en_short')}',
                            style: GoogleFonts.dmSans(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Upload Indicator
                if (_isUploading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black54,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),

                // Bottom Right Actions (Send Snap Button)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    onPressed: _isUploading ? null : _showImageSourceSelector,
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.camera_alt_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
