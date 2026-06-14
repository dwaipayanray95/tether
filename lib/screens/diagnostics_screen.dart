import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/fcm_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _loggingEnabled = LogService.isEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildLoggingToggle(),
          _buildTile(
            icon: Icons.copy_rounded,
            title: 'Copy Logs',
            subtitle: 'Copy log history to clipboard',
            onTap: _copyLogs,
          ),
          _buildTile(
            icon: Icons.delete_sweep_rounded,
            title: 'Clear Logs',
            subtitle: 'Permanently delete log history',
            onTap: _clearLogs,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Testing'),
          _buildTile(
            icon: Icons.notifications_active_outlined,
            title: 'Local Notification',
            subtitle: 'Triggers a local device notification',
            onTap: _testNotification,
          ),
          _buildTile(
            icon: Icons.wifi_tethering_rounded,
            title: 'FCM Push to Self',
            subtitle: 'Tests direct serverless FCM token loopback',
            onTap: _testFcmSelf,
          ),
          _buildTile(
            icon: Icons.favorite_rounded,
            title: 'FCM Push to Partner',
            subtitle: 'Sends a connection test to partner device',
            onTap: _testFcmPartner,
          ),
        ],
      ),
    );
  }

  Widget _buildLoggingToggle() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: SwitchListTile(
        value: _loggingEnabled,
        onChanged: (val) async {
          await LogService.setEnabled(val);
          setState(() => _loggingEnabled = val);
        },
        title: Text(
          'Enable Logging',
          style: GoogleFonts.dmSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textDark,
          ),
        ),
        subtitle: Text(
          'Track app events for troubleshooting',
          style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textMuted),
        ),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.bug_report_outlined,
              color: AppTheme.primary, size: 20),
        ),
        activeThumbColor: AppTheme.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Future<void> _copyLogs() async {
    final logs = await LogService.getLogs();
    await Clipboard.setData(ClipboardData(text: logs));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logs copied to clipboard')),
      );
    }
  }

  Future<void> _clearLogs() async {
    await LogService.clearLogs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logs cleared')),
      );
    }
  }

  Future<void> _testNotification() async {
    LogService.log('Triggering test notification');
    await NotificationService.showTest();
  }

  Future<void> _testFcmSelf() async {
    LogService.log('Triggering test FCM to Self');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final res = await FcmService.send(
      partnerName: 'self',
      title: '🔔 Diagnostic Test',
      body: 'Your direct FCM pipeline is perfectly configured!',
    );
    if (mounted) Navigator.pop(context); // dismiss loader
    
    _showResultDialog(
      title: 'FCM Self Test Result',
      success: res.success,
      message: res.message,
    );
  }

  Future<void> _testFcmPartner() async {
    final auth = AuthService();
    final partnerName = auth.partnerName.toLowerCase();
    LogService.log('Triggering test FCM to Partner: $partnerName');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final res = await FcmService.send(
      partnerName: partnerName,
      title: '💖 Connection Test from ${auth.myDisplayName}',
      body: 'Our direct connection is perfectly up and running!',
    );
    if (mounted) Navigator.pop(context); // dismiss loader
    
    _showResultDialog(
      title: 'FCM Partner Test Result',
      success: res.success,
      message: res.message,
    );
  }

  void _showResultDialog({required String title, required bool success, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.error_rounded,
              color: success ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
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
}
