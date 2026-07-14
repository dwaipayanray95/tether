import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class LogService {
  static bool _isEnabled = false;
  static File? _logFile;

  // The log file previously grew unbounded — with logging enabled across
  // several days of normal use (lifecycle events, presence updates, sync
  // backfills, etc. all logging on their own schedules), it became large
  // enough to be unwieldy to read/share for troubleshooting. Cap it and
  // self-trim from the front (oldest entries) once it grows past the cap,
  // keeping the on-device log a rolling recent-history window instead of a
  // permanent archive — Diagnostics' "Copy Logs" is for troubleshooting
  // what's happening now, not long-term storage.
  static const _maxLogBytes = 1 * 1024 * 1024; // 1MB
  static int _writesSinceTrimCheck = 0;
  static const _trimCheckInterval = 50;

  static bool get isEnabled => _isEnabled;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool('logging_enabled') ?? false;
      
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/app_logs.txt');
    } catch (e) {
      debugPrint('Failed to initialize log file: $e');
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logging_enabled', enabled);
      if (enabled) {
        await log('Logging enabled by user');
      }
    } catch (e) {
      debugPrint('Failed to save logging preference: $e');
    }
  }

  static Future<void> log(String message) async {
    if (!_isEnabled || _logFile == null) return;
    try {
      final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      await _logFile!.writeAsString('[$timestamp] $message\n', mode: FileMode.append);
      debugPrint('LOG: $message');
      _writesSinceTrimCheck++;
      if (_writesSinceTrimCheck >= _trimCheckInterval) {
        _writesSinceTrimCheck = 0;
        await _trimIfNeeded();
      }
    } catch (e) {
      debugPrint('Failed to write log: $e');
    }
  }

  /// Only checked every [_trimCheckInterval] writes (not every single
  /// call) — length()/readAsString() on every log line would be wasteful,
  /// and being off by up to that many lines' worth of size is harmless for
  /// a rolling troubleshooting log.
  static Future<void> _trimIfNeeded() async {
    final file = _logFile;
    if (file == null) return;
    final length = await file.length();
    if (length <= _maxLogBytes) return;

    final content = await file.readAsString();
    // Keep the newest half of the cap, not the newest ~everything — trimming
    // to just under the cap would mean re-trimming almost immediately on
    // the very next check interval.
    final keepFromChar = content.length - (_maxLogBytes ~/ 2);
    final tail = content.substring(keepFromChar > 0 ? keepFromChar : 0);
    // Drop the (likely partial) first line so every remaining line is whole.
    final firstNewline = tail.indexOf('\n');
    final clean = firstNewline == -1 ? tail : tail.substring(firstNewline + 1);
    await file.writeAsString(
        '[log trimmed — older entries dropped to keep this file manageable]\n$clean');
  }

  static Future<String> getLogs() async {
    if (_logFile == null) return 'Log file not initialized.';
    if (!await _logFile!.exists()) return 'No logs found.';
    try {
      return await _logFile!.readAsString();
    } catch (e) {
      return 'Error reading logs: $e';
    }
  }

  static Future<void> clearLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      try {
        await _logFile!.writeAsString('');
        await log('Logs cleared');
      } catch (e) {
        debugPrint('Failed to clear logs: $e');
      }
    }
  }
}
