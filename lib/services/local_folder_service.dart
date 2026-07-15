import 'dart:typed_data';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart' show SafDocumentFile;
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

/// Manages a user-picked, persistent "Tether" folder on the device's shared
/// storage (via Android's Storage Access Framework), used as a local-first
/// backup destination — independent of Google Drive.
///
/// Why this exists: app-private storage (getApplicationDocumentsDirectory,
/// used by LocalStorageService's snap cache and the local Drift DB) is
/// wiped by Android on uninstall. A SAF-picked folder lives outside the
/// app's private storage, so files written there survive an
/// uninstall/reinstall — the persisted URI *permission* is revoked on
/// uninstall (Android ties it to the app's package), but the files
/// themselves are untouched, so the user just re-picks the same folder
/// once after reinstalling to reconnect.
///
/// Mirrors the Drive "Tether" folder's structure: a `snaps/` subfolder and
/// a `backups/` subfolder.
class LocalFolderService {
  static const _rootUriKey = 'local_backup_folder_uri';

  final _safUtil = SafUtil();
  final _safStream = SafStream();

  Future<String?> _loadRootUri() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rootUriKey);
  }

  Future<void> _saveRootUri(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rootUriKey, uri);
  }

  Future<void> _clearRootUri() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rootUriKey);
  }

  /// True if a folder has been picked AND the app still holds a valid
  /// permission grant for it (the grant can be silently revoked by Android
  /// after long inactivity, or lost entirely across an uninstall/reinstall —
  /// in both cases the user needs to run [pickFolder] again).
  Future<bool> isConnected() async {
    final uri = await _loadRootUri();
    if (uri == null) return false;
    try {
      return await _safUtil.hasPersistedPermission(
        uri,
        checkRead: true,
        checkWrite: true,
      );
    } catch (e) {
      LogService.log('LocalFolderService: permission check failed: $e');
      return false;
    }
  }

  Future<String?> currentFolderUri() => _loadRootUri();

  /// Prompts the user to pick (or re-pick, after reinstall) a folder. Call
  /// this from a real user-initiated tap (Settings), same constraint as
  /// Android's other interactive-only permission dialogs in this app.
  Future<bool> pickFolder() async {
    try {
      final picked = await _safUtil.pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      if (picked == null) return false;
      await _saveRootUri(picked.uri);
      // Pre-create both subfolders now rather than lazily on first write,
      // so a later write failure can't be confused with "folder not set up".
      await _safUtil.mkdirp(picked.uri, ['snaps']);
      await _safUtil.mkdirp(picked.uri, ['backups']);
      LogService.log('LocalFolderService: connected to folder ${picked.uri}');
      return true;
    } catch (e) {
      LogService.log('LocalFolderService: pickFolder failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    await _clearRootUri();
  }

  Future<String?> _subfolderUri(String name) async {
    final root = await _loadRootUri();
    if (root == null) return null;
    try {
      final dir = await _safUtil.mkdirp(root, [name]);
      return dir.uri;
    } catch (e) {
      LogService.log('LocalFolderService: failed to reach "$name" subfolder: $e');
      return null;
    }
  }

  /// Writes [bytes] as [fileName] into the `backups/` subfolder, overwriting
  /// any existing file with that name. Returns false (not an exception) on
  /// any failure — callers treat the local backup as best-effort, same as
  /// the existing Drive path already does for its own failures.
  Future<bool> writeBackup(String fileName, Uint8List bytes) async {
    final dirUri = await _subfolderUri('backups');
    if (dirUri == null) return false;
    try {
      await _safStream.writeFileBytes(
        dirUri,
        fileName,
        'application/octet-stream',
        bytes,
        overwrite: true,
      );
      return true;
    } catch (e) {
      LogService.log('LocalFolderService: writeBackup failed: $e');
      return false;
    }
  }

  /// Writes [bytes] as [fileName] into the `snaps/` subfolder — mirrors the
  /// same write-through pattern as writeBackup, used alongside (not instead
  /// of) LocalStorageService's app-private snap cache.
  Future<bool> writeSnap(String fileName, Uint8List bytes, String mime) async {
    final dirUri = await _subfolderUri('snaps');
    if (dirUri == null) return false;
    try {
      await _safStream.writeFileBytes(dirUri, fileName, mime, bytes, overwrite: true);
      return true;
    } catch (e) {
      LogService.log('LocalFolderService: writeSnap failed: $e');
      return false;
    }
  }

  /// Lists files currently in the `backups/` subfolder — used by
  /// LocalDbHydrationService as a fallback recovery source when Drive is
  /// unavailable but a local backup exists.
  Future<List<SafDocumentFile>> listBackups() async {
    final dirUri = await _subfolderUri('backups');
    if (dirUri == null) return [];
    try {
      return await _safUtil.list(dirUri);
    } catch (e) {
      LogService.log('LocalFolderService: listBackups failed: $e');
      return [];
    }
  }

  Future<Uint8List?> readBackup(String fileUri) async {
    try {
      return await _safStream.readFileBytes(fileUri);
    } catch (e) {
      LogService.log('LocalFolderService: readBackup failed: $e');
      return null;
    }
  }
}
