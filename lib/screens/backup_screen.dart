import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/backup_cursor_model.dart';
import '../services/backup_cursor_store.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';

String _formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupCursor? _cursor;
  bool _isRunning = false;
  String? _resultMessage;
  bool? _lastRunSucceeded;

  @override
  void initState() {
    super.initState();
    _loadCursor();
  }

  Future<void> _loadCursor() async {
    await BackupService().reconcileCursorWithDriveIfNeeded();
    final cursor = await BackupCursorStore().load();
    if (mounted) setState(() => _cursor = cursor);
  }

  Future<void> _runBackupNow() async {
    setState(() {
      _isRunning = true;
      _resultMessage = null;
      _lastRunSucceeded = null;
    });

    final result = await BackupService().runBackup();
    await _loadCursor();

    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _resultMessage = result.localBackupWritten
          ? '${result.message} (local copy saved)'
          : result.message;
      _lastRunSucceeded = result.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lastBackupAt = _cursor?.lastBackupAt;
    final sizeText = _formatBytes(_cursor?.lastBackupSizeBytes);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_rounded,
                    color: AppTheme.primary, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Backup',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        lastBackupAt != null
                            ? DateFormat('MMMM d, yyyy \'at\' h:mm a')
                                .format(lastBackupAt)
                            : 'Never backed up yet',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                      if (lastBackupAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          sizeText,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_isRunning) ...[
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              child: LinearProgressIndicator(
                minHeight: 6,
                backgroundColor: AppTheme.divider,
                valueColor: AlwaysStoppedAnimation(AppTheme.primary),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Backing up…',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _runBackupNow,
                child: Text('Backup Now',
                    style: GoogleFonts.dmSans(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          if (_resultMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _lastRunSucceeded == true
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _lastRunSucceeded == true
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    color: _lastRunSucceeded == true
                        ? Colors.green
                        : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _resultMessage!,
                      style: GoogleFonts.dmSans(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Your messages, to-dos, and sticky notes are encrypted end-to-end '
            'and backed up to your Google Drive. Tether checks automatically '
            'every time you open the app, at most once every 24 hours — you '
            'only need to tap "Backup Now" if you want to back up sooner.',
            style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textMuted),
          ),
          // The MediaStore local-folder channel (LocalFolderService) is only
          // implemented natively on Android — there's no iOS handler for
          // "com.theawesomeray.tether/mediastore", so every call there
          // throws MissingPluginException and is swallowed to false/null.
          // Showing this card on iOS would promise a local copy that can
          // never actually exist.
          if (Platform.isAndroid) ...[
          const SizedBox(height: 32),
          Text(
            'Local Backup Folder',
            style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_special_rounded, color: AppTheme.primary, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Documents/Tether',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A copy of every backup is also saved here automatically, on your '
                        'device. It survives an uninstall/reinstall, and stays available '
                        'even if Google Drive is full or offline.',
                        style: GoogleFonts.dmSans(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ],
        ],
      ),
    );
  }
}
