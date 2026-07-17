import 'dart:io';
import 'package:flutter/services.dart';
import 'log_service.dart';

/// Manages an automatically-created "Documents/Tether" folder on the
/// device's shared storage, used as a local-first backup destination —
/// independent of Google Drive.
///
/// Why this exists: app-private storage (getApplicationDocumentsDirectory,
/// used by LocalStorageService's snap cache and the local Drift DB) is
/// wiped by Android on uninstall. This folder lives outside the app's
/// private storage, so files written there survive an uninstall/reinstall.
///
/// Deliberately implemented as a native MediaStore platform channel (see
/// MainActivity.kt), not the Storage Access Framework — SAF requires an
/// interactive folder-picker dialog before anything can be written, every
/// single install. MediaStore lets the folder be silently auto-created on
/// first write, with only a normal one-time permission grant and no picker
/// UI at all — much closer to how e.g. WhatsApp's Documents/WhatsApp folder
/// behaves. There is no "connect"/"pick folder" step for the user anymore;
/// this is always available.
///
/// Mirrors the Drive "Tether" folder's structure: a `snaps/` subfolder and
/// a `backups/` subfolder, both under Documents/Tether.
class LocalFolderService {
  static const _channel = MethodChannel('com.theawesomeray.tether/mediastore');
  static const _rootRelativePath = 'Documents/Tether';

  String get _backupsPath => '$_rootRelativePath/backups';
  String get _snapsPath => '$_rootRelativePath/snaps';

  /// Writes [bytes] as [fileName] into Documents/Tether/backups, overwriting
  /// any existing file with that name. Returns false (not an exception) on
  /// any failure — callers treat the local backup as best-effort, same as
  /// the existing Drive path already does for its own failures.
  Future<bool> writeBackup(String fileName, Uint8List bytes) =>
      _writeFile(_backupsPath, fileName, bytes, 'application/octet-stream');

  /// Writes [bytes] as [fileName] into Documents/Tether/snaps — mirrors the
  /// same write-through pattern as writeBackup, used alongside (not instead
  /// of) LocalStorageService's app-private snap cache.
  Future<bool> writeSnap(String fileName, Uint8List bytes, String mime) =>
      _writeFile(_snapsPath, fileName, bytes, mime);

  Future<Uint8List?> readBackup(String fileName) async {
    // No native handler for this channel exists on iOS (see MainActivity.kt
    // — Android-only) — short-circuit instead of relying on the platform
    // throwing MissingPluginException on every call.
    if (!Platform.isAndroid) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
          'readFile', {'relativePath': _backupsPath, 'fileName': fileName});
      return bytes;
    } catch (e) {
      LogService.log('LocalFolderService: readBackup failed: $e');
      return null;
    }
  }

  Future<bool> _writeFile(
      String relativePath, String fileName, Uint8List bytes, String mimeType) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('writeFile', {
        'relativePath': relativePath,
        'fileName': fileName,
        'mimeType': mimeType,
        'bytes': bytes,
      });
      return ok ?? false;
    } catch (e) {
      LogService.log('LocalFolderService: write to $relativePath/$fileName failed: $e');
      return false;
    }
  }
}
