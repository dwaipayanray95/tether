import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../services/local_storage_service.dart';
import '../theme/app_theme.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final LocalStorageService _storage = LocalStorageService();
  List<LocalSnap> _snaps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllSnaps();
  }

  Future<void> _loadAllSnaps() async {
    setState(() => _isLoading = true);
    final list = await _storage.loadSnaps();
    setState(() {
      _snaps = list;
      _isLoading = false;
    });
  }

  Future<void> _deleteSnap(LocalSnap snap) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppTheme.surface,
        title: Text(
          'Delete Snap?',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.bold, color: AppTheme.textDark),
        ),
        content: Text(
          'This will permanently delete the snap from your local gallery and Google Drive backup.',
          style: GoogleFonts.dmSans(color: AppTheme.textDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      HapticFeedback.heavyImpact();
      // Show loading indicator overlay
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );

      await _storage.deleteSnap(snap);
      
      if (mounted) {
        Navigator.pop(context); // Pop loading dialog
        _loadAllSnaps();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Snap deleted successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _viewSnapDetails(LocalSnap snap) {
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
              icon: const Icon(Icons.share_rounded, color: Colors.white, size: 24),
              onPressed: () async {
                HapticFeedback.lightImpact();
                final text = snap.caption.isNotEmpty ? snap.caption : 'Tether Polaroid Snap';
                // ignore: deprecated_member_use
                await Share.shareXFiles(
                  [XFile(snap.imagePath)],
                  text: text,
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 26),
              onPressed: () {
                Navigator.pop(ctx);
                _deleteSnap(snap);
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 3.5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(snap.imagePath),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Polaroid Gallery',
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
            fontSize: 22,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _snaps.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.photo_library_outlined, size: 64, color: AppTheme.textMuted),
                      const SizedBox(height: 16),
                      Text(
                        'Your gallery is empty.',
                        style: GoogleFonts.dmSans(color: AppTheme.textMuted, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Saved snaps will appear here.',
                        style: GoogleFonts.dmSans(color: AppTheme.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 108 / 135,
                  ),
                  itemCount: _snaps.length,
                  itemBuilder: (context, index) {
                    final snap = _snaps[index];
                    return GestureDetector(
                      onTap: () => _viewSnapDetails(snap),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(snap.imagePath),
                            fit: BoxFit.cover,
                            // Grid cells are ~160-180 logical px wide — decoding
                            // full camera-resolution photos for every cell in a
                            // scrolling 2-column grid is the single biggest
                            // cause of jank here.
                            cacheWidth: 360,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
