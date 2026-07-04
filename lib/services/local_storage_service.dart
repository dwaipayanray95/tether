import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'google_drive_service.dart';
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
  final GoogleDriveService _driveService = GoogleDriveService();

  Future<Directory> get _snapsDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/snaps');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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

  Future<void> deleteSnap(LocalSnap snap) async {
    try {
      LogService.log('Local Storage: Deleting snap ${snap.id}');
      // 1. Delete local files
      final imgFile = File(snap.imagePath);
      final jsonFile = File(snap.imagePath.replaceAll('.png', '.json'));
      
      if (await imgFile.exists()) await imgFile.delete();
      if (await jsonFile.exists()) await jsonFile.delete();

      // 2. Delete cloud backup if sync file ID exists
      if (snap.driveFileId != null) {
        await _driveService.deleteFile(snap.driveFileId!);
      }
      LogService.log('Local Storage: Snap ${snap.id} deleted successfully');
    } catch (e) {
      LogService.log('Local Storage Error: Failed to delete snap ${snap.id}: $e');
    }
  }
}
