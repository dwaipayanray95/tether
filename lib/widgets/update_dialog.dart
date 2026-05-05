import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  static Future<void> checkAndShow(BuildContext context) async {
    final update = await UpdateService.checkForUpdate();
    if (update == null || !context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: update),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  double? _progress;
  bool _done = false;
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
    // Opens "Install unknown apps" screen scoped to Tether specifically
    await Permission.requestInstallPackages.request();
    final granted = await Permission.requestInstallPackages.isGranted;
    if (mounted) setState(() => _canInstall = granted);
  }

  Future<void> _download() async {
    // Re-check permission right before downloading
    final granted = await Permission.requestInstallPackages.isGranted;
    if (!granted) {
      setState(() => _canInstall = false);
      return;
    }

    setState(() => _progress = 0);
    try {
      final error = await UpdateService.downloadAndInstall(
        widget.info.downloadUrl,
        (p) => setState(() => _progress = p),
      );
      if (error != null) {
        setState(() => _progress = null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
                'Install failed. Enable "Install unknown apps" for Tether in Settings.'),
            backgroundColor: const Color(0xFFE8715A),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 6),
          ));
        }
      } else {
        setState(() => _done = true);
      }
    } catch (_) {
      setState(() => _progress = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Download failed. Try again.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
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
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 14),
              ),

              // ── Install permission warning ──────────────────────────────
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
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF5D4037)),
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
                          icon:
                              const Icon(Icons.settings_rounded, size: 16),
                          label: const Text(
                              'Allow Tether to install apps',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Release notes ───────────────────────────────────────────
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
                const SizedBox(height: 6),
                Text(
                  widget.info.releaseNotes!,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textDark,
                      height: 1.5),
                ),
              ],

              // ── Download progress ───────────────────────────────────────
              if (_progress != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: AppTheme.divider,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primary),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _done
                      ? 'Done! Follow the install prompt.'
                      : '${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: _progress != null
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later',
                    style: TextStyle(color: AppTheme.textMuted)),
              ),
              ElevatedButton(
                onPressed: _canInstall ? _download : _openInstallSettings,
                child:
                    Text(_canInstall ? 'Update now' : 'Allow first'),
              ),
            ],
    );
  }
}
