import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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
import '../../services/local_storage_service.dart';
import '../../services/google_drive_service.dart';
import '../../screens/gallery_screen.dart';
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
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );

      if (pickedFile == null) return;
      _showCaptionDialog(File(pickedFile.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick photo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showCaptionDialog(File imageFile) {
    final captionCtrl = TextEditingController();
    bool saveLocally = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: AppTheme.surface,
          title: Text(
            'Add a Caption',
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    imageFile,
                    height: 200,
                    width: 200,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: captionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Caption (Cursive)',
                    hintText: 'e.g. Thinking of you!',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 40,
                ),
                CheckboxListTile(
                  title: Text(
                    'Save to Local & Drive',
                    style: GoogleFonts.dmSans(fontSize: 14, color: AppTheme.textDark),
                  ),
                  value: saveLocally,
                  activeColor: AppTheme.primary,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) {
                    setDialogState(() {
                      saveLocally = val ?? true;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () async {
                final caption = captionCtrl.text.trim();
                Navigator.pop(dialogCtx); // close dialog
                
                setState(() => _isUploading = true);
                HapticFeedback.mediumImpact();
                
                try {
                  final originalBytes = await imageFile.readAsBytes();
                  final base64Photo = base64Encode(originalBytes);
                  
                  final myKey = _auth.myName.toLowerCase(); // 'ray' or 'aproo'
                  await _firestore.sendSnap(coupleId, myKey, base64Photo, caption);

                  final date = DateTime.now();

                  // Save locally as a polaroid and backup to Google Drive
                  if (saveLocally) {
                    try {
                      final polaroidBytes = await _renderPolaroidPNG(originalBytes, caption, date);
                      final localSnap = await LocalStorageService().saveSnap(polaroidBytes, caption, date);

                      // Asynchronously upload to Google Drive in background
                      GoogleDriveService()
                          .uploadSnap(polaroidBytes, 'snap_${localSnap.id}.png')
                          .then((driveFileId) {
                            if (driveFileId != null) {
                              LocalStorageService().updateDriveFileId(localSnap.id, driveFileId);
                            }
                          });
                    } catch (e) {
                      // Silently catch local storage errors
                    }
                  }

                  // Trigger high priority FCM push notification to partner
                  final partnerName = _auth.partnerName.toLowerCase();
                  await FcmService.send(
                    partnerName: partnerName,
                    title: '📷 New Polaroid Snap!',
                    body: '${_auth.myDisplayName} sent you a Polaroid. Open Tether to view!',
                    type: 'snap',
                  );

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Polaroid sent successfully! 📸'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to send Polaroid: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                } finally {
                  if (mounted) {
                    setState(() => _isUploading = false);
                  }
                }
              },
              child: const Text('Send Polaroid'),
            ),
          ],
        ),
      ),
    );
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

  // ── Polaroid Image Generation (On-Demand for Downloads) ─────────────────────

  Future<ui.Image> _loadImage(Uint8List bytes) async {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      return completer.complete(img);
    });
    return completer.future;
  }

  Future<Uint8List> _renderPolaroidPNG(Uint8List imageBytes, String caption, DateTime date) async {
    final originalImage = await _loadImage(imageBytes);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Draw solid white polaroid background (1080x1350)
    final framePaint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1080, 1350), framePaint);

    // 2. Draw photo cropped into square of 960x960 at (60, 60)
    final srcWidth = originalImage.width;
    final srcHeight = originalImage.height;
    double srcX = 0;
    double srcY = 0;
    double side = 0;

    if (srcWidth > srcHeight) {
      side = srcHeight.toDouble();
      srcX = (srcWidth - side) / 2;
    } else {
      side = srcWidth.toDouble();
      srcY = (srcHeight - side) / 2;
    }

    canvas.drawImageRect(
      originalImage,
      Rect.fromLTWH(srcX, srcY, side, side),
      const Rect.fromLTWH(60, 60, 960, 960),
      Paint(),
    );

    // 3. Draw inner border around photo
    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(const Rect.fromLTWH(60, 60, 960, 960), borderPaint);

    // 4. Draw Date/Time digital LCD stamp on bottom-right of photo
    final dateString = DateFormat("yy  M  d   HH:mm").format(date);
    final dateStyle = GoogleFonts.orbitron(
      color: const Color(0xFFFF5A00), // Glowing retro camera orange
      fontSize: 28,
      fontWeight: FontWeight.bold,
      shadows: [
        const Shadow(
          color: Color(0xFFFF5A00),
          blurRadius: 5,
        ),
      ],
    );
    final dateSpan = TextSpan(text: dateString, style: dateStyle);
    final datePainter = TextPainter(
      text: dateSpan,
      textDirection: ui.TextDirection.ltr,
    );
    datePainter.layout();
    datePainter.paint(
      canvas,
      Offset(1080 - 60 - datePainter.width - 25, 1020 - datePainter.height - 25),
    );

    // 5. Draw Cursive caption at the bottom
    if (caption.isNotEmpty) {
      final captionStyle = GoogleFonts.caveat(
        color: const Color(0xFF2D2D2D),
        fontSize: 56,
        fontWeight: FontWeight.w600,
      );
      final captionSpan = TextSpan(text: caption, style: captionStyle);
      final captionPainter = TextPainter(
        text: captionSpan,
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      captionPainter.layout(maxWidth: 960);
      
      final cx = (1080 - captionPainter.width) / 2;
      final cy = 1080 + (270 - captionPainter.height) / 2;
      captionPainter.paint(canvas, Offset(cx, cy));
    }

    // 6. Export
    final picture = recorder.endRecording();
    final img = await picture.toImage(1080, 1350);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // ── Immersive Full-Screen Viewer ───────────────────────────────────────────

  void _showFullScreenViewer(Uint8List imageBytes, String caption, DateTime date, String title) {
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
                  // Render the full polaroid in memory dynamically on-demand!
                  final polaroidBytes = await _renderPolaroidPNG(imageBytes, caption, date);
                  
                  final tempDir = await getTemporaryDirectory();
                  final file = File('${tempDir.path}/tether_polaroid_${DateTime.now().millisecondsSinceEpoch}.png');
                  await file.writeAsBytes(polaroidBytes);

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
                        content: Text('Error rendering polaroid: $e'),
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
            child: AspectRatio(
              aspectRatio: 1080 / 1350,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Image.memory(
                                imageBytes,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Text(
                                DateFormat('yy  M  d   HH:mm').format(date),
                                style: GoogleFonts.vt323(
                                  color: const Color(0xFFFF5A00),
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      color: const Color(0xFFFF5A00).withValues(alpha: 0.8),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 80,
                      child: Center(
                        child: Text(
                          caption,
                          style: GoogleFonts.caveat(
                            color: const Color(0xFF2D2D2D),
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
        final partnerPhotoBase64 = data?['${partnerKey}LatestPhoto'] as String?;
        final partnerCaption = data?['${partnerKey}Caption'] as String? ?? '';
        final partnerSentAt = data?['${partnerKey}SentAt'] as Timestamp?;

        Uint8List? partnerImageBytes;
        if (partnerPhotoBase64 != null) {
          try {
            partnerImageBytes = base64Decode(partnerPhotoBase64);
          } catch (_) {}
        }

        return Container(
          width: double.infinity,
          height: 180,
          decoration: BoxDecoration(
            color: partnerImageBytes != null ? Colors.white : const Color(0xFF1E1716),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                if (partnerImageBytes != null && partnerSentAt != null)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => _showFullScreenViewer(
                        partnerImageBytes!,
                        partnerCaption,
                        partnerSentAt.toDate(),
                        'Snap from $partnerName',
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, top: 12, right: 12, bottom: 44),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Image.memory(
                                  partnerImageBytes,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              // Live handwritten timestamp stamp on home screen card image
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Builder(
                                    builder: (context) {
                                      final timeAgoStr = timeago.format(partnerSentAt.toDate(), locale: 'en_short');
                                      return Text(
                                        timeAgoStr == 'now' ? 'now' : '$timeAgoStr ago',
                                        style: GoogleFonts.dmSans(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      );
                                    }
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

                // Polaroid caption text drawn live using text widgets at the bottom row of homescreen card
                if (partnerImageBytes != null)
                  Positioned(
                    bottom: 0,
                    left: 16,
                    right: 64, // Leave space for camera FAB
                    height: 44,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        partnerCaption.isNotEmpty ? partnerCaption : 'A live photo...',
                        style: GoogleFonts.caveat(
                          color: const Color(0xFF2D2D2D),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

                // Gallery / Album Button (Top Right Overlay)
                Positioned(
                  top: 12,
                  right: 12,
                  child: ClipOval(
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const GalleryScreen()),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.photo_library_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom Right Actions (Send Snap Button)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: FloatingActionButton.small(
                    onPressed: _isUploading ? null : _showImageSourceSelector,
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.camera_alt_rounded, size: 18),
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
