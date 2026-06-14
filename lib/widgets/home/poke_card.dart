import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

class PokeCard extends StatefulWidget {
  const PokeCard({super.key});

  @override
  State<PokeCard> createState() => _PokeCardState();
}

class _PokeCardState extends State<PokeCard>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  final _firestore = FirestoreService();
  late AnimationController _pokeController;
  late Animation<double> _pokeScale;

  bool _pokeCooldown = false;

  @override
  void initState() {
    super.initState();
    _pokeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _pokeScale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pokeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pokeController.dispose();
    super.dispose();
  }

  Future<void> _sendPoke() async {
    if (_pokeCooldown) return;

    final myUid = _auth.currentUser!.uid;

    setState(() => _pokeCooldown = true);

    await _pokeController.forward();
    await _pokeController.reverse();
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.heavyImpact();

    await _firestore.sendPoke(coupleId, myUid, _auth.myName);
    final myKey = _auth.isRay ? 'ray' : 'aproo';
    await _firestore.updatePresence(myKey);

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _pokeCooldown = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _auth.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.pokeStatusStream(coupleId),
      builder: (context, snap) {
        final lastPokeFrom = snap.data?.data()?['lastFrom'] as String?;
        final isLastPokedByMe = lastPokeFrom == myUid;

        String bannerText;
        if (_pokeCooldown) {
          bannerText = 'You have poked them';
        } else if (isLastPokedByMe) {
          bannerText = 'You poked ${_auth.partnerDisplayName}! Poke again? 💕';
        } else {
          bannerText = 'Let them know you\'re thinking of them';
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Poke ${_auth.partnerDisplayName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: _pokeCooldown ? AppTheme.textMuted : null,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bannerText,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ScaleTransition(
                scale: _pokeScale,
                child: GestureDetector(
                  onTap: _pokeCooldown ? null : _sendPoke,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _pokeCooldown
                          ? AppTheme.divider.withValues(alpha: 0.2)
                          : AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.touch_app_rounded,
                      color: _pokeCooldown ? AppTheme.textMuted : AppTheme.primary,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
