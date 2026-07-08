import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/log_service.dart';
import '../services/crypto_service.dart';
import '../services/google_drive_service.dart';
import '../services/backup_service.dart';
import '../services/foreground_backup_scheduler.dart';
import '../services/firestore_service.dart';
import '../services/local_sync_service.dart';
import '../config/env_config.dart';
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
            icon: Icons.security_rounded,
            title: 'E2EE Encryption Test',
            subtitle: 'Checks encryption status and tests secure channel',
            onTap: _testE2EE,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Backup'),
          _buildTile(
            icon: Icons.backup_rounded,
            title: 'Run Backup Now',
            subtitle: 'Manually triggers one incremental backup cycle',
            onTap: _runBackupNow,
          ),
          _buildTile(
            icon: Icons.visibility_rounded,
            title: 'Inspect Backup State',
            subtitle: 'Shows cursor, Drive generations, and live-vs-backup counts',
            onTap: _inspectBackup,
          ),
          _buildTile(
            icon: Icons.restore_rounded,
            title: 'Restore Preview',
            subtitle: 'Downloads + merges backup with live data (does not apply it)',
            onTap: _previewRestore,
          ),
          _buildTile(
            icon: Icons.schedule_rounded,
            title: 'Run Backup If Due',
            subtitle: 'Exercises the real 24h due-check used on app open/resume',
            onTap: _runBackupIfDue,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Local DB (Phase 1 — shadow mode)'),
          _buildTile(
            icon: Icons.storage_rounded,
            title: 'Inspect Local DB',
            subtitle: 'Row counts vs. live Firestore — verifies the sync engine before any screen reads from it',
            onTap: _inspectLocalDb,
          ),
        ],
      ),
    );
  }

  Widget _buildLoggingToggle() {
    // Background color must live on the Material (not an outer DecoratedBox)
    // so SwitchListTile's ink splashes paint on top of it instead of being
    // hidden underneath — see Flutter's own "ListTile ink splashes may be
    // invisible" warning this fixes.
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: AppTheme.surface,
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

  Future<void> _testE2EE() async {
    LogService.log('Running E2EE Diagnostic Test');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    final cryptoService = CryptoService();
    final driveService = GoogleDriveService();

    final localPubKey = await cryptoService.getPublicKey();
    final localPrivKey = await cryptoService.getPrivateKey();
    final localKeysOk = localPubKey != null && localPrivKey != null;

    final partnerPubKey = await cryptoService.fetchPartnerPublicKey();
    final partnerKeyOk = partnerPubKey != null;

    final backup = await driveService.restoreKeyBackup();
    final backupOk = backup != null;

    bool channelOk = false;
    String channelDetails = '';

    if (localKeysOk && partnerPubKey != null) {
      try {
        final sharedKey = await cryptoService.getSharedKey(partnerPubKey);
        const testStr = 'Tether E2EE Diagnostic Channel Test String';
        final encrypted = await cryptoService.encryptText(testStr, sharedKey);
        final decrypted = await cryptoService.decryptText(encrypted, sharedKey);
        if (decrypted == testStr) {
          channelOk = true;
          channelDetails = 'AES-GCM (256-bit) shared secret key verified.';
        } else {
          channelDetails = 'Decryption mismatch error.';
        }
      } catch (e) {
        channelDetails = 'Crypto failure: $e';
      }
    } else {
      channelDetails = 'Unavailable (local keys or partner key missing).';
    }

    if (mounted) Navigator.pop(context); // Dismiss loader
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(
              (localKeysOk && partnerKeyOk && backupOk && channelOk)
                  ? Icons.verified_user_rounded
                  : Icons.gpp_maybe_rounded,
              color: (localKeysOk && partnerKeyOk && backupOk && channelOk)
                  ? Colors.green
                  : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text('E2EE Diagnostics', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCheckrow('Local Keypair status', localKeysOk),
            _buildCheckrow('Partner Public Key synced', partnerKeyOk),
            _buildCheckrow('Google Drive Backup verified', backupOk),
            _buildCheckrow('Encryption Channel status', channelOk),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Channel details:\n$channelDetails',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _runBackupNow() async {
    LogService.log('Diagnostics: manually triggering backup run');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    final result = await BackupService().runBackup();

    if (mounted) Navigator.pop(context); // dismiss loader
    if (!mounted) return;

    _showResultDialog(
      title: 'Backup Run Result',
      success: result.success,
      message: result.success
          ? '${result.message}\n\nTotals now in backup: ${result.todos} todos, '
              '${result.comments} comments, ${result.messages} messages, '
              '${result.stickyNotes} sticky notes.'
          : result.message,
    );
  }

  Future<void> _inspectBackup() async {
    LogService.log('Diagnostics: inspecting backup state');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    final inspection = await BackupService().inspect();

    if (mounted) Navigator.pop(context); // dismiss loader
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Backup State', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Drive files', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
              Text(
                inspection.latestExists
                    ? 'latest_backup exists'
                    : 'latest_backup does NOT exist yet (no backup run yet)',
              ),
              Text('Occupied prior generations: ${inspection.occupiedGenerations.isEmpty ? "none" : inspection.occupiedGenerations.join(", ")}'),
              const SizedBox(height: 12),
              Text('Counts (backup vs. live Firestore)', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
              Text('Todos: ${inspection.backupTodoCount ?? "—"} vs ${inspection.liveTodoCount}'),
              Text('Messages: ${inspection.backupMessageCount ?? "—"} vs ${inspection.liveMessageCount}'),
              Text('Sticky notes: ${inspection.backupStickyNoteCount ?? "—"} vs ${inspection.liveStickyNoteCount}'),
              const SizedBox(height: 12),
              Text('Local cursor', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
              Text('Todos synced at: ${inspection.cursor.todosSyncedAt ?? "never"}'),
              Text('Messages synced at: ${inspection.cursor.messagesSyncedAt ?? "never"}'),
              Text('Sticky notes synced at: ${inspection.cursor.stickyNotesSyncedAt ?? "never"}'),
              Text('Last backup at: ${inspection.cursor.lastBackupAt ?? "never"}'),
              if (inspection.error != null) ...[
                const SizedBox(height: 12),
                Text(inspection.error!,
                    style: const TextStyle(fontSize: 12, color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _previewRestore() async {
    LogService.log('Diagnostics: previewing restore-from-backup');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    final merged = await BackupService().restoreFromBackup(dryRun: true);

    if (mounted) Navigator.pop(context); // dismiss loader
    if (!mounted) return;

    _showResultDialog(
      title: 'Restore Preview',
      success: merged != null,
      message: merged != null
          ? 'Merged backup + live Firestore would produce: '
              '${merged.todos.length} todos, ${merged.comments.length} comments, '
              '${merged.messages.length} messages, ${merged.stickyNotes.length} sticky notes.\n\n'
              'True dry run — nothing was applied to a local cache (that piece '
              'isn\'t built yet) and the sync cursor was left untouched.'
          : 'No backup found on Drive, or partner key unavailable — check logs.',
    );
  }

  Future<void> _runBackupIfDue() async {
    LogService.log('Diagnostics: running the real due-check used on app open/resume');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    await ForegroundBackupScheduler.runIfDue();

    if (mounted) Navigator.pop(context); // dismiss loader
    if (!mounted) return;

    _showResultDialog(
      title: 'Due-Check Complete',
      success: true,
      message:
          'Ran the same check that fires on every app open/resume: skips '
          'if the last backup was under 24h ago, otherwise runs one. Check '
          'the app log or "Inspect Backup State" to see which happened.',
    );
  }

  Future<void> _inspectLocalDb() async {
    LogService.log('Diagnostics: inspecting local DB state');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    final sync = LocalSyncService();
    final firestore = FirestoreService();
    const coupleId = EnvConfig.coupleId;

    final localMessages = await sync.messageDao.count();
    final localTodos = await sync.todoDao.count();
    final localComments = await sync.commentDao.count();
    final localStickyNotes = await sync.stickyNoteDao.count();

    int? liveMessages, liveTodos, liveComments, liveStickyNotes;
    String? error;
    try {
      liveMessages = await firestore.countMessages(coupleId);
      liveTodos = await firestore.countTodos(coupleId);
      liveComments = await firestore.countComments();
      liveStickyNotes = await firestore.countStickyNotes(coupleId);
    } catch (e) {
      error = 'Failed to fetch live Firestore counts: $e';
    }

    if (mounted) Navigator.pop(context); // dismiss loader
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Local DB State', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Counts (local DB vs. live Firestore)', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
              Text('Messages: $localMessages vs ${liveMessages ?? "—"}'),
              Text('Todos: $localTodos vs ${liveTodos ?? "—"}'),
              Text('Comments: $localComments vs ${liveComments ?? "—"}'),
              Text('Sticky notes: $localStickyNotes vs ${liveStickyNotes ?? "—"}'),
              const SizedBox(height: 12),
              Text(
                'Messages will legitimately run slightly behind live count '
                'right after a fresh sign-in, until the one-time full-history '
                'backfill finishes — re-check after a few seconds if it '
                'looks low.',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error, style: const TextStyle(fontSize: 12, color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckrow(String label, bool isOk) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isOk ? Colors.green : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textDark,
                fontWeight: isOk ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
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
            Expanded(child: Text(title)),
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
    // Same fix as _buildLoggingToggle() — background belongs on Material,
    // not an outer DecoratedBox, so ListTile's ink splash renders visibly.
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: AppTheme.surface,
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
      ),
    );
  }
}
