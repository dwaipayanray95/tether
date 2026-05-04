import 'package:flutter/material.dart';
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
  double? _progress; // null = not downloading, 0-1 = downloading
  bool _done = false;

  Future<void> _download() async {
    setState(() => _progress = 0);
    try {
      final error = await UpdateService.downloadAndInstall(
        widget.info.downloadUrl,
        (p) => setState(() => _progress = p),
      );
      if (error != null) {
        // Installation failed — likely needs "Install unknown apps" enabled
        setState(() => _progress = null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
              'To install: go to Settings → Apps → Tether → Install unknown apps → Allow',
            ),
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version ${widget.info.version} is ready.',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          if (widget.info.releaseNotes != null &&
              widget.info.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(widget.info.releaseNotes!,
                style:
                    const TextStyle(fontSize: 13, color: AppTheme.textDark)),
          ],
          if (_progress != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: AppTheme.divider,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _done
                  ? 'Done! Follow the install prompt.'
                  : '${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
      actions: _progress != null
          ? null // hide buttons while downloading
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later',
                    style: TextStyle(color: AppTheme.textMuted)),
              ),
              ElevatedButton(
                onPressed: _download,
                child: const Text('Update now'),
              ),
            ],
    );
  }
}
