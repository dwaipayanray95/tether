import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildSectionHeader('Profile'),
          _buildTile(
            icon: Icons.person_outline_rounded,
            title: 'Partner Info',
            subtitle: 'Names, anniversary, and more',
            onTap: () {}, // Future feature
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Fun Stuff'),
          _buildTile(
            icon: Icons.auto_awesome_rounded,
            title: 'Trivia',
            subtitle: 'Test your knowledge about each other',
            onTap: () {}, // Future feature
          ),
          _buildTile(
            icon: Icons.history_rounded,
            title: 'Memories',
            subtitle: 'Coming soon...',
            onTap: () {},
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Diagnostics'),
          _buildTile(
            icon: Icons.bug_report_outlined,
            title: 'Diagnostics',
            subtitle: 'Logging and troubleshooting tools',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Account'),
          _buildTile(
            icon: Icons.logout_rounded,
            title: 'Sign out',
            subtitle: 'Logged in as ${auth.myName}',
            textColor: Colors.redAccent,
            onTap: () => _showSignOutDialog(context, auth),
          ),
          const SizedBox(height: 40),
          Center(
            child: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) {
                final version = snap.data?.version ?? '…';
                return Text(
                  'Tether v$version',
                  style: GoogleFonts.dmSans(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.textMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: textColor ?? AppTheme.primary, size: 20),
        ),
        title: Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor ?? AppTheme.textDark,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppTheme.textMuted, size: 20),
      ),
    );
  }

  void _showSignOutDialog(BuildContext context, AuthService auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text('Signing out as ${auth.myName}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await auth.signOut();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            child: const Text('Sign out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
