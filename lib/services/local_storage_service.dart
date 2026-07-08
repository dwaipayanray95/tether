import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'log_service.dart';

class LocalSnap {
  final String id; // Timestamp based unique ID
  final String caption;
  final DateTime date;
  final String? driveFileId;
  final String imagePath;

  LocalSnap({
    required this.id,
    required this.caption,
    required this.date,
    this.driveFileId,
    required this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'caption': caption,
        'date': date.toIso8601String(),
        'driveFileId': driveFileId,
      };

  factory LocalSnap.fromJson(String id, String imagePath, Map<String, dynamic> json) {
    return LocalSnap(
      id: id,
      caption: json['caption'] as String? ?? '',
      date: DateTime.parse(json['date'] as String? ?? DateTime.now().toIso8601String()),
      driveFileId: json['driveFileId'] as String?,
      imagePath: imagePath,
    );
  }
}

class LocalStorageService {
  Future<Directory> get _snapsDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/snaps');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> get _pendingDeletionsFile async {
    final dir = await _snapsDir;
    return File('${dir.path}/pending_drive_deletions.json');
  }

  Future<LocalSnap> saveSnap(Uint8List imageBytes, String caption, DateTime date, {String? driveFileId}) async {
    final dir = await _snapsDir;
    final id = date.millisecondsSinceEpoch.toString();
    final imagePath = '${dir.path}/snap_$id.png';
    final jsonPath = '${dir.path}/snap_$id.json';

    // 1. Write files locally
    await File(imagePath).writeAsBytes(imageBytes);
    
    final snap = LocalSnap(
      id: id,
      caption: caption,
      date: date,
      driveFileId: driveFileId,
      imagePath: imagePath,
    );

    await File(jsonPath).writeAsString(jsonEncode(snap.toJson()));
    LogService.log('Local Storage: Snap $id saved locally');
    return snap;
  }

  Future<List<LocalSnap>> loadSnaps() async {
    try {
      final dir = await _snapsDir;
      final files = dir.listSync();
      final List<LocalSnap> snaps = [];

      for (final file in files) {
        if (file is File && file.path.endsWith('.json')) {
          final id = file.path.split('snap_').last.split('.json').first;
          final imagePath = file.path.replaceAll('.json', '.png');
          
          if (await File(imagePath).exists()) {
            final content = await file.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            snaps.add(LocalSnap.fromJson(id, imagePath, json));
          }
        }
      }

      // Sort chronological descending (newest first)
      snaps.sort((a, b) => b.date.compareTo(a.date));
      return snaps;
    } catch (e) {
      LogService.log('Local Storage Error: Failed to load snaps: $e');
      return [];
    }
  }

  Future<void> updateDriveFileId(String id, String driveFileId) async {
    try {
      final dir = await _snapsDir;
      final jsonPath = '${dir.path}/snap_$id.json';
      final file = File(jsonPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        json['driveFileId'] = driveFileId;
        await file.writeAsString(jsonEncode(json));
        LogService.log('Local Storage: Snap $id metadata updated with driveFileId $driveFileId');
      }
    } catch (e) {
      LogService.log('Local Storage Error: Failed to update metadata for snap $id: $e');
    }
  }

  /// Deletes the local snap immediately. If it had already been uploaded to
  /// Drive, the Drive file itself is NOT deleted here — that would mean
  /// every gallery delete is its own Drive round trip (the same per-action
  /// Drive-touch pattern the rest of the backup pipeline deliberately
  /// avoids, and a source of the Google auth UI flash). Instead the
  /// driveFileId is recorded as a pending deletion, and the next
  /// [BackupService.runBackup] run cleans it up in the same batch as
  /// everything else it already syncs to Drive.
  Future<void> deleteSnap(LocalSnap snap) async {
    try {
      LogService.log('Local Storage: Deleting snap ${snap.id}');

      // Read latest JSON from disk to get non-stale driveFileId from background upload
      final dir = await _snapsDir;
      final jsonFile = File('${dir.path}/snap_${snap.id}.json');
      String? driveFileId = snap.driveFileId;

      if (await jsonFile.exists()) {
        final content = await jsonFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        if (json['driveFileId'] != null) {
          driveFileId = json['driveFileId'] as String;
        }
      }

      // 1. Delete local files
      final imgFile = File(snap.imagePath);
      if (await imgFile.exists()) await imgFile.delete();
      if (await jsonFile.exists()) await jsonFile.delete();

      // 2. Defer the Drive-side cleanup to the next backup run.
      if (driveFileId != null) {
        await _recordPendingDeletion(driveFileId);
      }
      LogService.log('Local Storage: Snap ${snap.id} deleted successfully');
    } catch (e) {
      LogService.log('Local Storage Error: Failed to delete snap ${snap.id}: $e');
    }
  }

  // ── Backup pipeline hooks (see BackupService._syncSnaps) ────────────────

  /// Local snaps that exist on disk but have never been uploaded to Drive
  /// (saved/downloaded since the last backup run, or the very first ever).
  Future<List<LocalSnap>> pendingUploadSnaps() async {
    final snaps = await loadSnaps();
    return snaps.where((s) => s.driveFileId == null).toList();
  }

  /// Ids already present locally, by their `snap_{id}.png` filename — used
  /// to figure out which Drive snap files are missing locally (e.g. after a
  /// fresh install, since local storage is wiped on reinstall but Drive
  /// isn't).
  Future<Set<String>> localSnapIds() async {
    final snaps = await loadSnaps();
    return snaps.map((s) => s.id).toSet();
  }

  /// Saves a snap recovered from Drive — same as saveSnap() but keeps the
  /// Drive file's own id-derived filename instead of minting a new one from
  /// the current time, so re-running this is idempotent and the restored
  /// snap is immediately marked as already uploaded (no redundant re-upload
  /// on the next backup run).
  Future<void> saveRecoveredSnap(
      String id, Uint8List imageBytes, String driveFileId) async {
    final dir = await _snapsDir;
    final imagePath = '${dir.path}/snap_$id.png';
    final jsonPath = '${dir.path}/snap_$id.json';
    final date = DateTime.fromMillisecondsSinceEpoch(int.tryParse(id) ?? 0);

    await File(imagePath).writeAsBytes(imageBytes);
    // Caption isn't recoverable — uploadSnap() only ever uploads the raw
    // PNG bytes, never the caption, so a snap restored from Drive alone
    // necessarily comes back with a blank caption.
    final snap = LocalSnap(
        id: id, caption: '', date: date, driveFileId: driveFileId, imagePath: imagePath);
    await File(jsonPath).writeAsString(jsonEncode(snap.toJson()));
  }

  Future<List<String>> pendingDeletionDriveFileIds() async {
    try {
      final file = await _pendingDeletionsFile;
      if (!await file.exists()) return [];
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      return list.cast<String>();
    } catch (e) {
      LogService.log('Local Storage Error: Failed to read pending deletions: $e');
      return [];
    }
  }

  Future<void> clearPendingDeletion(String driveFileId) async {
    try {
      final file = await _pendingDeletionsFile;
      final current = await pendingDeletionDriveFileIds();
      current.remove(driveFileId);
      await file.writeAsString(jsonEncode(current));
    } catch (e) {
      LogService.log('Local Storage Error: Failed to clear pending deletion: $e');
    }
  }

  Future<void> _recordPendingDeletion(String driveFileId) async {
    final file = await _pendingDeletionsFile;
    final current = await pendingDeletionDriveFileIds();
    if (!current.contains(driveFileId)) {
      current.add(driveFileId);
      await file.writeAsString(jsonEncode(current));
    }
  }
}
