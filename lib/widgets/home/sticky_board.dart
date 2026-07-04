import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

// ── Pastel colours shared between board and archive ───────────────────────────

const List<Color> stickyPastels = [
  Color(0xFFFFF0EE),
  Color(0xFFFEF9C3),
  Color(0xFFF0FDF4),
  Color(0xFFEFF6FF),
  Color(0xFFFFF0F5),
];

// ── Individual sticky note tile ───────────────────────────────────────────────

class StickyNoteTile extends StatelessWidget {
  final String id;
  final String text;
  final int colorIndex;
  final String author;
  final bool isMe;
  final DateTime? date;
  final VoidCallback onDelete;

  const StickyNoteTile({
    super.key,
    required this.id,
    required this.text,
    required this.colorIndex,
    required this.author,
    required this.isMe,
    required this.date,
    required this.onDelete,
  });

  void _showReadNoteDialog(BuildContext context, Color paperColor) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
              decoration: BoxDecoration(
                color: paperColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(4, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Text(
                        text,
                        style: GoogleFonts.caveat(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF3E2D29),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '— $author',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF8C7A76),
                        ),
                      ),
                      if (date != null)
                        Builder(
                          builder: (context) {
                            final istDate = date!.toUtc().add(
                                const Duration(hours: 5, minutes: 30));
                            return Text(
                              '${DateFormat('d MMMM y, h:mm a').format(istDate)} IST',
                              style: GoogleFonts.dmSans(
                                fontSize: 10,
                                color: const Color(0xFF8C7A76),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: -8,
              child: Container(
                width: 70,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 2,
                    )
                  ],
                ),
              ),
            ),
            Positioned(
              top: -12,
              right: -12,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      )
                    ],
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: AppTheme.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = stickyPastels[colorIndex % stickyPastels.length];

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showReadNoteDialog(context, color);
      },
      onLongPress: () {
        HapticFeedback.heavyImpact();
        onDelete();
      },
      child: Container(
        width: 145,
        margin: const EdgeInsets.only(right: 14),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -24,
              left: 40,
              child: Container(
                width: 36,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      text,
                      style: GoogleFonts.caveat(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF3E2D29),
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '— $author',
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF8C7A76),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (date != null)
                      Builder(
                        builder: (context) {
                          final istDate = date!.toUtc().add(
                              const Duration(hours: 5, minutes: 30));
                          return Text(
                            DateFormat('d MMM').format(istDate),
                            style: GoogleFonts.dmSans(
                              fontSize: 9,
                              color: const Color(0xFF8C7A76),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sticky Board (board + header + archive sheet) ─────────────────────────────

class StickyBoard extends StatefulWidget {
  const StickyBoard({super.key});

  @override
  State<StickyBoard> createState() => StickyBoardState();
}

class StickyBoardState extends State<StickyBoard> {
  final _auth = AuthService();
  final _firestore = FirestoreService();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _firestore.stickyNotesStream(coupleId);
  }

  // ── Add Note ──────────────────────────────────────────────────────────────

  void _showAddNoteSheet() {
    final textCtrl = TextEditingController();
    int selectedColor = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pin a Sticky Note',
                    style: GoogleFonts.dmSans(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close_rounded,
                        color: AppTheme.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: stickyPastels[selectedColor],
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: textCtrl,
                  maxLines: 4,
                  maxLength: 90,
                  style: GoogleFonts.caveat(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2E2421),
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Write something sweet...',
                    hintStyle: TextStyle(color: Colors.black26),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    counterText: '',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select note paper color',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(stickyPastels.length, (idx) {
                  final isSelected = selectedColor == idx;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setSheetState(() => selectedColor = idx);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: stickyPastels[idx],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : AppTheme.divider,
                          width: isSelected ? 2.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded,
                              color: AppTheme.primary, size: 18)
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final text = textCtrl.text.trim();
                    if (text.isNotEmpty) {
                      HapticFeedback.mediumImpact();
                      _firestore.addStickyNote(
                        coupleId,
                        text,
                        _auth.currentUser!.uid,
                        _auth.myName,
                        selectedColor,
                      );
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Pin Note'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Archive Note ──────────────────────────────────────────────────────────

  void _confirmArchiveNote(String noteId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Peel off note?'),
        content: const Text(
            'This sticky note will be moved to the archive instead of deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              HapticFeedback.heavyImpact();
              _firestore.archiveStickyNote(coupleId, noteId);
              Navigator.pop(context);
            },
            child: const Text('Peel off'),
          ),
        ],
      ),
    );
  }

  // ── Archive Sheet ─────────────────────────────────────────────────────────

  void showArchiveSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scrollCtrl) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore.stickyNotesStream(coupleId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final archived = snapshot.data!.docs.where((d) {
              return d.data()['isArchived'] == true;
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.archive_rounded,
                          color: AppTheme.primary, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Sticky Notes Archive',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.divider),
                Expanded(
                  child: archived.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inventory_2_outlined,
                                  size: 48, color: AppTheme.textMuted),
                              const SizedBox(height: 12),
                              Text(
                                'No archived notes yet.',
                                style: GoogleFonts.dmSans(
                                    color: AppTheme.textMuted, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.0,
                          ),
                          itemCount: archived.length,
                          itemBuilder: (context, index) {
                            final doc = archived[index];
                            final id = doc.id;
                            final text = doc['text'] as String? ?? '';
                            final colorIdx = doc['colorIndex'] as int? ?? 0;
                            final author =
                                doc['createdByName'] as String? ?? 'Partner';
                            final paperColor = stickyPastels[
                                colorIdx % stickyPastels.length];

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: paperColor,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      text,
                                      style: GoogleFonts.dmSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textDark,
                                      ),
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'From $author',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textMuted,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GestureDetector(
                                            onTap: () async {
                                              HapticFeedback.mediumImpact();
                                              await _firestore
                                                  .restoreStickyNote(
                                                      coupleId, id);
                                            },
                                            child: const Icon(
                                              Icons.unarchive_rounded,
                                              size: 16,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () {
                                              HapticFeedback.heavyImpact();
                                              showDialog(
                                                context: sheetCtx,
                                                builder: (_) => AlertDialog(
                                                  title: const Text(
                                                      'Delete permanently?'),
                                                  content: const Text(
                                                      'This will erase the sticky note memory forever.'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              sheetCtx),
                                                      child:
                                                          const Text('Keep it'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () async {
                                                        Navigator.pop(sheetCtx);
                                                        await _firestore
                                                            .permanentlyDeleteStickyNote(
                                                                coupleId, id);
                                                      },
                                                      child: const Text(
                                                          'Delete',
                                                          style: TextStyle(
                                                              color:
                                                                  Colors.red)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                            child: const Icon(
                                              Icons.delete_forever_rounded,
                                              size: 16,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Add note tile ──────────────────────────────────────────────────────────

  Widget _buildAddNoteTile() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _showAddNoteSheet();
      },
      child: Container(
        width: 85,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.2),
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              'Add Note',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Board ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SizedBox(
            height: 155,
            child: Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SizedBox(
            height: 155,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final docs = (snapshot.data?.docs ?? []).where((d) {
          return d.data()['isArchived'] != true;
        }).toList();

        return SizedBox(
          height: 155,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: docs.length + 1,
            itemBuilder: (context, index) {
              if (index == docs.length) {
                return _buildAddNoteTile();
              }
              final doc = docs[index];
              final id = doc.id;
              final text = doc['text'] as String? ?? '';
              final colorIdx = doc['colorIndex'] as int? ?? 0;
              final author = doc['createdByName'] as String? ?? 'Partner';
              final authorUid = doc['createdBy'] as String? ?? '';
              final date = (doc['createdAt'] as Timestamp?)?.toDate();

              return StickyNoteTile(
                id: id,
                text: text,
                colorIndex: colorIdx,
                author: author,
                isMe: authorUid == _auth.currentUser!.uid,
                date: date,
                onDelete: () => _confirmArchiveNote(id),
              );
            },
          ),
        );
      },
    );
  }
}
