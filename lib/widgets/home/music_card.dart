import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/music_sync_service.dart';
import '../../theme/app_theme.dart';

// ── Rotating Vinyl ─────────────────────────────────────────────────────────────

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
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[900],
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          gradient: const RadialGradient(
            colors: [Color(0xFF333333), Color(0xFF111111)],
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(4),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary,
            ),
            child: const Center(
              child: Icon(Icons.music_note_rounded, color: Colors.white, size: 10),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Audio Visualizer ───────────────────────────────────────────────────────────

class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({super.key});

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<double> _heightMultiplier = [0.2, 0.8, 0.5, 0.9, 0.4, 0.7, 0.3];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(7, (index) {
            final phase = index * 0.15;
            final value = (_ctrl.value + phase) % 1.0;
            final height = 4.0 + (value * 16.0 * _heightMultiplier[index]);
            return Container(
              width: 3.5,
              height: height,
              margin: const EdgeInsets.only(right: 2.5),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Music Card ─────────────────────────────────────────────────────────────────

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

        final partnerMusic = partnerRaw?['music'] != null
            ? Map<String, dynamic>.from(partnerRaw!['music'] as Map)
            : null;
        final myMusic = myRaw?['music'] != null
            ? Map<String, dynamic>.from(myRaw!['music'] as Map)
            : null;

        return Container(
          padding: const EdgeInsets.all(20),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.music_note_rounded,
                        color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Now Playing',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (partnerMusic != null && partnerMusic['isPlaying'] == true) ...[
                Row(
                  children: [
                    RotatingVinyl(isPlaying: true),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            partnerMusic['track'] ?? 'Unknown Track',
                            style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'by ${partnerMusic['artist'] ?? 'Unknown Artist'}',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          const AudioVisualizer(),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    const RotatingVinyl(isPlaying: false),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        '$partnerName isn\'t listening to music right now.',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: AppTheme.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: AppTheme.divider, height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: myMusic != null && myMusic['isPlaying'] == true
                        ? Row(
                            children: [
                              const Icon(Icons.radio_button_checked_rounded,
                                  color: Colors.green, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Sharing: "${myMusic['track']}"',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textDark,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Let $partnerName know what you\'re playing!',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                            ),
                          ),
                  ),
                  if (myMusic != null && myMusic['isPlaying'] == true)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        MusicSyncService.clearMusic();
                      },
                      icon: const Icon(Icons.clear_rounded,
                          size: 14, color: AppTheme.primary),
                      label: const Text(
                        'Stop',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    )
                  else
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _showManualMusicDialog(context),
                      icon: const Icon(Icons.share_rounded,
                          size: 14, color: AppTheme.primary),
                      label: const Text(
                        'Share',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: AppTheme.divider, height: 1),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_rounded,
                        size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Syncs automatically with Spotify, YT Music & Apple Music! For Spotify, ensure "Device Broadcast Status" is enabled in Spotify Settings.',
                        style: GoogleFonts.dmSans(
                          fontSize: 10.5,
                          color: AppTheme.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
