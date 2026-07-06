import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/partner_profile_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/log_service.dart';
import '../theme/app_theme.dart';

class PartnerInfoScreen extends StatefulWidget {
  const PartnerInfoScreen({super.key});

  @override
  State<PartnerInfoScreen> createState() => _PartnerInfoScreenState();
}

class _PartnerInfoScreenState extends State<PartnerInfoScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  final _firestore = FirestoreService();
  String? _partnerUid;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _auth.getPartnerUid().then((uid) {
      if (mounted) setState(() => _partnerUid = uid);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _auth.currentUser?.uid ?? '';
    const couple = coupleId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner Info'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.primary,
          labelStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Me — ${_auth.myDisplayName}'),
            Tab(text: _auth.partnerDisplayName),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: _buildAnniversaryCard(couple),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildProfileCard(
                      docStream: _firestore.userDocStream(myUid),
                      editable: true,
                      uid: myUid,
                    ),
                  ],
                ),
                _partnerUid == null
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          _buildProfileCard(
                            docStream: _firestore.userDocStream(_partnerUid!),
                            editable: false,
                            uid: _partnerUid!,
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Anniversary ──────────────────────────────────────────────────────────

  Widget _buildAnniversaryCard(String couple) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.coupleDocStream(couple),
      builder: (context, snap) {
        final ts = snap.data?.data()?['anniversary'] as Timestamp?;
        final anniversary = ts?.toDate();
        return GestureDetector(
          onTap: () => _pickAnniversary(couple, anniversary),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite_rounded,
                    color: AppTheme.primary, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Anniversary',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        anniversary != null
                            ? DateFormat('MMMM d, yyyy').format(anniversary)
                            : 'Tap to set your anniversary',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.edit_rounded,
                    color: AppTheme.textMuted, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAnniversary(String couple, DateTime? current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
            onPrimary: Colors.white,
            onSurface: AppTheme.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null) return;
    await _firestore.updateAnniversary(couple, date);
  }

  // ── Profile card ─────────────────────────────────────────────────────────

  Widget _buildProfileCard({
    required Stream<DocumentSnapshot<Map<String, dynamic>>> docStream,
    required bool editable,
    required String uid,
  }) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docStream,
      builder: (context, snap) {
        final profile =
            PartnerProfile.fromMap(snap.data?.data()?['profile'] as Map<String, dynamic>?);
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(
                icon: Icons.cake_rounded,
                label: 'Birthday',
                value: profile.birthday != null
                    ? '${DateFormat('MMMM d, yyyy').format(profile.birthday!)}  ·  ${zodiacSignFor(profile.birthday!)}'
                    : null,
                onTap: editable ? () => _pickBirthday(uid, profile) : null,
              ),
              _infoRow(
                icon: Icons.checkroom_rounded,
                label: 'Clothing Sizes',
                value: profile.clothingSizes.isEmpty
                    ? null
                    : profile.clothingSizes.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('  ·  '),
                onTap: editable ? () => _editClothingSizes(uid, profile) : null,
              ),
              _infoRow(
                icon: Icons.hiking_rounded,
                label: 'Shoe Size',
                value: profile.shoeSize,
                onTap: editable
                    ? () => _editText(
                        uid, profile, 'shoeSize', 'Shoe Size', profile.shoeSize)
                    : null,
              ),
              _infoRow(
                icon: Icons.diamond_rounded,
                label: 'Ring Size',
                value: profile.ringSize,
                onTap: editable
                    ? () => _editText(
                        uid, profile, 'ringSize', 'Ring Size', profile.ringSize)
                    : null,
              ),
              _infoRow(
                icon: Icons.warning_amber_rounded,
                label: 'Allergies',
                value: profile.allergies.isEmpty
                    ? null
                    : profile.allergies.join(', '),
                onTap: editable
                    ? () => _editList(uid, profile, 'allergies', 'Allergies',
                        profile.allergies)
                    : null,
              ),
              _infoRow(
                icon: Icons.no_food_rounded,
                label: 'Food Dislikes',
                value: profile.foodDislikes.isEmpty
                    ? null
                    : profile.foodDislikes.join(', '),
                onTap: editable
                    ? () => _editList(uid, profile, 'foodDislikes',
                        'Food Dislikes', profile.foodDislikes)
                    : null,
              ),
              _infoRow(
                icon: Icons.restaurant_rounded,
                label: 'Favorite Foods',
                value: profile.favoriteFoods.isEmpty
                    ? null
                    : profile.favoriteFoods.join(', '),
                onTap: editable
                    ? () => _editList(uid, profile, 'favoriteFoods',
                        'Favorite Foods', profile.favoriteFoods)
                    : null,
              ),
              _infoRow(
                icon: Icons.palette_rounded,
                label: 'Favorite Color',
                value: profile.favoriteColor,
                onTap: editable
                    ? () => _editText(uid, profile, 'favoriteColor',
                        'Favorite Color', profile.favoriteColor)
                    : null,
              ),
              _infoRow(
                icon: Icons.movie_rounded,
                label: 'Top 5 Favorite Movies',
                value: profile.favoriteMovies.isEmpty
                    ? null
                    : profile.favoriteMovies
                        .asMap()
                        .entries
                        .map((e) => '${e.key + 1}. ${e.value}')
                        .join('   '),
                onTap: editable
                    ? () => _editList(uid, profile, 'favoriteMovies',
                        'Top 5 Favorite Movies', profile.favoriteMovies,
                        maxItems: maxFavoriteMovies)
                    : null,
                isLast: true,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String? value,
    VoidCallback? onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(bottom: BorderSide(color: AppTheme.divider)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primary, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value?.isNotEmpty == true ? value! : 'Not set',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: value?.isNotEmpty == true
                          ? AppTheme.textDark
                          : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Editing ──────────────────────────────────────────────────────────────

  Future<void> _saveProfile(String uid, PartnerProfile updated) async {
    try {
      await _firestore.updateProfile(uid, updated.toMap());
    } catch (e) {
      LogService.log('Failed to update partner profile: $e');
    }
  }

  Future<void> _pickBirthday(String uid, PartnerProfile profile) async {
    final date = await showDatePicker(
      context: context,
      initialDate: profile.birthday ?? DateTime(2000),
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
            onPrimary: Colors.white,
            onSurface: AppTheme.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null) return;
    await _saveProfile(uid, profile.copyWith(birthday: date));
  }

  Future<void> _editClothingSizes(String uid, PartnerProfile profile) async {
    final entries = Map<String, String>.from(profile.clothingSizes);
    final proportionCtrl = TextEditingController();
    final sizeCtrl = TextEditingController();

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Clothing Sizes',
                  style: GoogleFonts.dmSans(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (entries.isNotEmpty)
                ...entries.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${e.key}: ${e.value}',
                                style: GoogleFonts.dmSans(fontSize: 14)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () =>
                                setSheetState(() => entries.remove(e.key)),
                          ),
                        ],
                      ),
                    )),
              const SizedBox(height: 8),
              TextField(
                controller: proportionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Proportion (e.g. Top, Bottom, Dress)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: sizeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Size (letter or number, e.g. M or 32)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: letterSizes
                    .map((s) => ActionChip(
                          label: Text(s),
                          onPressed: () => sizeCtrl.text = s,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    final proportion = proportionCtrl.text.trim();
                    final size = sizeCtrl.text.trim();
                    if (proportion.isEmpty || size.isEmpty) return;
                    setSheetState(() {
                      entries[proportion] = size;
                      proportionCtrl.clear();
                      sizeCtrl.clear();
                    });
                  },
                  child: const Text('Add Size'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx, entries),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null) return;
    await _saveProfile(uid, profile.copyWith(clothingSizes: result));
  }

  Future<void> _editList(
    String uid,
    PartnerProfile profile,
    String field,
    String title,
    List<String> current, {
    int? maxItems,
  }) async {
    final items = List<String>.from(current);
    final itemCtrl = TextEditingController();

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.dmSans(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (items.isNotEmpty)
                ...items.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${e.key + 1}. ${e.value}',
                                style: GoogleFonts.dmSans(fontSize: 14)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () =>
                                setSheetState(() => items.removeAt(e.key)),
                          ),
                        ],
                      ),
                    )),
              if (maxItems == null || items.length < maxItems)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: itemCtrl,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (v) {
                          if (v.trim().isEmpty) return;
                          setSheetState(() {
                            items.add(v.trim());
                            itemCtrl.clear();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle_rounded,
                          color: AppTheme.primary),
                      onPressed: () {
                        final v = itemCtrl.text.trim();
                        if (v.isEmpty) return;
                        setSheetState(() {
                          items.add(v);
                          itemCtrl.clear();
                        });
                      },
                    ),
                  ],
                )
              else
                Text(
                  'Maximum of $maxItems reached',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppTheme.textMuted),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx, items),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null) return;

    PartnerProfile updated;
    switch (field) {
      case 'allergies':
        updated = profile.copyWith(allergies: result);
        break;
      case 'foodDislikes':
        updated = profile.copyWith(foodDislikes: result);
        break;
      case 'favoriteFoods':
        updated = profile.copyWith(favoriteFoods: result);
        break;
      case 'favoriteMovies':
        updated = profile.copyWith(favoriteMovies: result);
        break;
      default:
        return;
    }
    await _saveProfile(uid, updated);
  }

  Future<void> _editText(String uid, PartnerProfile profile, String field,
      String title, String? current) async {
    final ctrl = TextEditingController(text: current ?? '');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.dmSans(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    PartnerProfile updated;
    switch (field) {
      case 'shoeSize':
        updated = profile.copyWith(shoeSize: result);
        break;
      case 'ringSize':
        updated = profile.copyWith(ringSize: result);
        break;
      case 'favoriteColor':
        updated = profile.copyWith(favoriteColor: result);
        break;
      default:
        return;
    }
    await _saveProfile(uid, updated);
  }
}
