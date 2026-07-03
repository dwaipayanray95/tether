import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/music_sync_service.dart';
import '../../theme/app_theme.dart';

class RotatingVinyl extends StatefulWidget {
  final bool isPlaying;
  const RotatingVinyl({super.key, required this.isPlaying});

  @override
  State<RotatingVinyl> createState() => _RotatingVinylState();
}

class _RotatingVinylState extends State<RotatingVinyl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    if (widget.isPlaying) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant RotatingVinyl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying) {
      _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[900],
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
          gradient: const RadialGradient(
            colors: [Color(0xFF333333), Color(0xFF111111)],
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary,
            ),
            child: const Center(
              child: Icon(Icons.music_note_rounded, color: Colors.white, size: 8),
            ),
          ),
        ),
      ),
    );
  }
}

class MusicCard extends StatelessWidget {
  const MusicCard({super.key});

  void _showManualMusicDialog(BuildContext context) {
    final trackCtrl = TextEditingController();
    final artistCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.share_rounded,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Share song'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'What song are you listening to right now? It will appear on your partner\'s home screen.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: trackCtrl,
              decoration: const InputDecoration(
                hintText: 'Song title (e.g. Blinding Lights)',
                labelText: 'Song title',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: artistCtrl,
              decoration: const InputDecoration(
                hintText: 'Artist name (e.g. The Weeknd)',
                labelText: 'Artist',
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final track = trackCtrl.text.trim();
              final artist = artistCtrl.text.trim();
              if (track.isNotEmpty && artist.isNotEmpty) {
                HapticFeedback.mediumImpact();
                MusicSyncService.updateMusicManually(track, artist);
                Navigator.pop(context);
              }
            },
            child: const Text('Share Now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final partnerName = auth.partnerDisplayName;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService().presenceStream(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final rayPresence = data?['ray'] as Map<String, dynamic>?;
        final aprooPresence = data?['aproo'] as Map<String, dynamic>?;

        final partnerRaw = auth.isRay ? aprooPresence : rayPresence;
        final myRaw = auth.isRay ? rayPresence : aprooPresence;

        final partnerMusic = partnerRaw?['music'] as Map<String, dynamic>?;
        final myMusic = myRaw?['music'] as Map<String, dynamic>?;

        final partnerPlaying = partnerMusic != null && partnerMusic['isPlaying'] == true;
        final myPlaying = myMusic != null && myMusic['isPlaying'] == true;

        return Container(
          width: double.infinity,
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Vinyl rotation indicator
              RotatingVinyl(isPlaying: partnerPlaying),
              const SizedBox(width: 14),

              // Track metadata / Status
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (partnerPlaying) ...[
                      Text(
                        partnerMusic['track'] ?? 'Unknown Track',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'by ${partnerMusic['artist'] ?? 'Unknown Artist'}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      Text(
                        '$partnerName isn\'t sharing music',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Action button (Share / Stop)
              const SizedBox(width: 8),
              if (myPlaying)
                IconButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    MusicSyncService.clearMusic();
                  },
                  icon: const Icon(Icons.stop_circle_rounded,
                      color: AppTheme.primary, size: 28),
                  tooltip: 'Stop Sharing',
                )
              else
                IconButton(
                  onPressed: () => _showManualMusicDialog(context),
                  icon: const Icon(Icons.music_note_rounded,
                      color: AppTheme.primary, size: 26),
                  tooltip: 'Share Music',
                ),
            ],
          ),
        );
      },
    );
  }
}
