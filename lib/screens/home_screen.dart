import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/home/compass_card.dart';
import '../widgets/home/music_card.dart';
import '../widgets/home/poke_card.dart';
import '../widgets/home/quick_actions.dart';
import '../widgets/home/sticky_board.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int) onNavigate;
  final void Function(String messageId)? onSelectMessage;

  const HomeScreen({
    super.key,
    required this.onNavigate,
    this.onSelectMessage,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthService();
  final _firestore = FirestoreService();

  // Only the header still needs presence for the online dot + last-seen text.
  // Everything else is owned by its own card widget.
  Timestamp? _rayLastSeen;
  Timestamp? _aprooLastSeen;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _presenceSub;

  // Key to call showArchiveSheet() on the StickyBoard
  final GlobalKey<_StickyBoardState> _stickyBoardKey =
      GlobalKey<_StickyBoardState>();

  @override
  void initState() {
    super.initState();
    _presenceSub = _firestore.presenceStream().listen((snap) {
      final data = snap.data();
      if (mounted && data != null) {
        setState(() {
          final r = data['ray'] as Map<String, dynamic>?;
          final a = data['aproo'] as Map<String, dynamic>?;
          _rayLastSeen = r?['lastSeen'] as Timestamp?;
          _aprooLastSeen = a?['lastSeen'] as Timestamp?;
        });
      }
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    super.dispose();
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final partnerName = _auth.partnerDisplayName;
    final partnerLastSeen = _auth.isRay ? _aprooLastSeen : _rayLastSeen;
    final partnerOnline = partnerLastSeen != null &&
        DateTime.now().difference(partnerLastSeen.toDate()).inMinutes < 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(greeting,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textMuted)),
            Text('Raayyy & Aproo',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                )),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: partnerOnline
                        ? Colors.green
                        : AppTheme.textMuted.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  partnerOnline
                      ? '$partnerName is active now'
                      : (partnerLastSeen == null
                          ? '$partnerName is offline'
                          : '$partnerName was active ${timeago.format(partnerLastSeen.toDate(), locale: 'en_short')}'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SearchScreen(
                    onNavigate: widget.onNavigate,
                    onSelectMessage: widget.onSelectMessage,
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.search_rounded,
                    color: AppTheme.primary, size: 22),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.favorite,
                    color: AppTheme.primary, size: 22),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Sticky board header row ───────────────────────────────────────────────

  Widget _buildStickyHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Our Sticky Board',
          style: GoogleFonts.playfairDisplay(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        GestureDetector(
          onTap: () => _stickyBoardKey.currentState?.showArchiveSheet(),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.archive_rounded,
                color: AppTheme.primary, size: 20),
          ),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 14),
              const CompassCard(),
              const SizedBox(height: 18),
              _buildStickyHeader(),
              const SizedBox(height: 10),
              StickyBoard(key: _stickyBoardKey),
              const SizedBox(height: 14),
              const MusicCard(),
              const SizedBox(height: 14),
              const PokeCard(),
              const SizedBox(height: 14),
              QuickActions(onNavigate: widget.onNavigate),
            ],
          ),
        ),
      ),
    );
  }
}

// Re-export the StickyBoard state type so the GlobalKey works.
// ignore: library_private_types_in_public_api
typedef _StickyBoardState = StickyBoardState;
