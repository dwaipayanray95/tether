import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

// ── Public entry-point ────────────────────────────────────────────────────────

class UpdateDialog {
  static Future<void> checkAndShow(BuildContext context) async {
    final update = await UpdateService.checkForUpdate();
    if (update == null || !context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReleaseNotesDialog(info: update),
    );
  }
}

// ── Release notes dialog ──────────────────────────────────────────────────────

class _ReleaseNotesDialog extends StatefulWidget {
  final UpdateInfo info;
  const _ReleaseNotesDialog({required this.info});

  @override
  State<_ReleaseNotesDialog> createState() => _ReleaseNotesDialogState();
}

class _ReleaseNotesDialogState extends State<_ReleaseNotesDialog> {
  bool _canInstall = true;

  @override
  void initState() {
    super.initState();
    _checkInstallPermission();
  }

  Future<void> _checkInstallPermission() async {
    final granted = await Permission.requestInstallPackages.isGranted;
    if (mounted) setState(() => _canInstall = granted);
  }

  Future<void> _openInstallSettings() async {
    await Permission.requestInstallPackages.request();
    final granted = await Permission.requestInstallPackages.isGranted;
    if (mounted) setState(() => _canInstall = granted);
  }

  void _startDownload() {
    // Close THIS dialog, then open the download-progress dialog.
    Navigator.of(context).pop();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(info: widget.info),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update_rounded,
                color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('Update available'),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.45,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version ${widget.info.version} is ready.',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
              ),

              // ── Install permission warning ─────────────────────────────────
              if (!_canInstall) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFB74D)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFE65100), size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Permission needed',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE65100),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tether needs permission to install updates directly. Tap below — takes 2 seconds.',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF5D4037)),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65100),
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _openInstallSettings,
                          icon: const Icon(Icons.settings_rounded, size: 16),
                          label: const Text('Allow Tether to install apps',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Release notes ──────────────────────────────────────────────
              if (widget.info.releaseNotes != null &&
                  widget.info.releaseNotes!.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  "What's new",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.3,
                  ),
                ),
                MarkdownBody(
                  data: widget.info.releaseNotes!,
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 13, color: AppTheme.textDark, height: 1.5),
                    h1: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    h2: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                    listBullet: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              const Text('Later', style: TextStyle(color: AppTheme.textMuted)),
        ),
        ElevatedButton(
          onPressed: _canInstall ? _startDownload : _openInstallSettings,
          child: Text(_canInstall ? 'Update now' : 'Allow first'),
        ),
      ],
    );
  }
}

// ── Download progress dialog ──────────────────────────────────────────────────

class _DownloadDialog extends StatefulWidget {
  final UpdateInfo info;
  const _DownloadDialog({required this.info});

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double _progress = 0;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _done = false;
      _error = null;
    });
    try {
      final error = await UpdateService.downloadAndInstall(
        widget.info.downloadUrl,
        (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (error != null) {
        setState(() => _error = error);
      } else {
        setState(() => _done = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _done || _error != null, // prevent back-dismiss mid-download
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _done
                      ? Icons.check_rounded
                      : _error != null
                          ? Icons.error_outline_rounded
                          : Icons.download_rounded,
                  color: _error != null ? Colors.red : AppTheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                _done
                    ? 'Download complete!'
                    : _error != null
                        ? 'Download failed'
                        : 'Downloading update…',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _done
                    ? 'Follow the install prompt to update Tether.'
                    : _error != null
                        ? "Make sure you've allowed Tether to install apps in Settings."
                        : 'Version ${widget.info.version}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textMuted, height: 1.4),
              ),
              const SizedBox(height: 24),

              // Progress bar (hidden when done or errored)
              if (!_done && _error == null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: AppTheme.divider,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${(_progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary),
                ),
              ],

              // Done: just a close button (installer will take over)
              if (_done) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Got it'),
                  ),
                ),
              ],

              // Error: retry + dismiss
              if (_error != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Dismiss'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _download,
                        child: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
