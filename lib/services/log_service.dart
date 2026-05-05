import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class LogService {
  static bool _isEnabled = false;
  static File? _logFile;

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
    } catch (e) {
      debugPrint('Failed to write log: $e');
    }
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
