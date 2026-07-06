import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/partner_profile_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../screens/partner_info_screen.dart';

const int _totalProfileFields = 9;

int _filledFieldCount(PartnerProfile p) {
  var count = 0;
  if (p.birthday != null) count++;
  if (p.clothingSizes.isNotEmpty) count++;
  if (p.shoeSize?.isNotEmpty == true) count++;
  if (p.ringSize?.isNotEmpty == true) count++;
  if (p.allergies.isNotEmpty) count++;
  if (p.foodDislikes.isNotEmpty) count++;
  if (p.favoriteFoods.isNotEmpty) count++;
  if (p.favoriteColor?.isNotEmpty == true) count++;
  if (p.favoriteMovies.isNotEmpty) count++;
  return count;
}

class ProfileCompletionBar extends StatelessWidget {
  const ProfileCompletionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final firestore = FirestoreService();
    final uid = auth.currentUser?.uid ?? '';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore.userDocStream(uid),
      builder: (context, snap) {
        final profile = PartnerProfile.fromMap(
            snap.data?.data()?['profile'] as Map<String, dynamic>?);
        final filled = _filledFieldCount(profile);
        if (filled >= _totalProfileFields) return const SizedBox.shrink();

        final progress = filled / _totalProfileFields;
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PartnerInfoScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Text(
                  'Complete your profile',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: AppTheme.divider,
                      valueColor:
                          const AlwaysStoppedAnimation(AppTheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$filled/$_totalProfileFields',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
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
