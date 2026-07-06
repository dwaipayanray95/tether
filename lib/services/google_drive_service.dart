import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'auth_service.dart';
import 'log_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleDriveService {
  final Dio _dio = Dio();
  final AuthService _auth = AuthService();

  // Helper to obtain OAuth token
  Future<String> _getAccessToken() async {
    final googleUser = await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (googleUser == null) {
      throw Exception('Google Sign-In user is not available.');
    }
    final authorization = await googleUser.authorizationClient.authorizeScopes([
      'https://www.googleapis.com/auth/drive.file',
      'https://www.googleapis.com/auth/drive.appdata',
    ]);
    final token = authorization.accessToken;
    if (token == null) {
      throw Exception('Failed to obtain Google access token.');
    }
    return token;
  }

  // ── Drive Folder Management ────────────────────────────────────────────────

  Future<String> _getOrCreateFolder(String token, String folderName, {String? parentId}) async {
    // 1. Search for folder
    String query = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    if (parentId != null) {
      query += " and '$parentId' in parents";
    }
    
    final searchResponse = await _dio.get(
      'https://www.googleapis.com/drive/v3/files',
      queryParameters: {'q': query, 'fields': 'files(id)'},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final files = searchResponse.data['files'] as List?;
    if (files != null && files.isNotEmpty) {
      return files.first['id'] as String;
    }

    // 2. Create folder if not found
    final Map<String, dynamic> metadata = {
      'name': folderName,
      'mimeType': 'application/vnd.google-apps.folder',
    };
    if (parentId != null) {
      metadata['parents'] = [parentId];
    }

    final createResponse = await _dio.post(
      'https://www.googleapis.com/drive/v3/files',
      data: metadata,
      options: Options(headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }),
    );

    return createResponse.data['id'] as String;
  }

  Future<String> _getSnapsFolderId(String token) async {
    final parentId = await _getOrCreateFolder(token, 'Tether');
    return await _getOrCreateFolder(token, 'snaps', parentId: parentId);
  }

  // ── Snap Backup ────────────────────────────────────────────────────────────

  Future<String?> uploadSnap(Uint8List imageBytes, String fileName) async {
    try {
      LogService.log('Google Drive: Initiating snap backup for $fileName');
      final token = await _getAccessToken();
      final folderId = await _getSnapsFolderId(token);

      final metadata = jsonEncode({
        'name': fileName,
        'parents': [folderId],
      });

      const boundary = 'tether_boundary';
      final header = '\r\n--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: image/png\r\n\r\n';
      const footer = '\r\n--$boundary--\r\n';

      final bodyBytes = [
        ...utf8.encode(header),
        ...imageBytes,
        ...utf8.encode(footer),
      ];

      final response = await _dio.post(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
        data: Stream.fromIterable([bodyBytes]),
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'multipart/related; boundary=$boundary',
            'Content-Length': bodyBytes.length.toString(),
          },
        ),
      );

      final driveFileId = response.data['id'] as String?;
      LogService.log('Google Drive: Snap successfully backed up with ID: $driveFileId');
      return driveFileId;
    } catch (e) {
      LogService.log('Google Drive Error: Failed to upload snap: $e');
      return null;
    }
  }

  Future<bool> deleteFile(String fileId) async {
    try {
      LogService.log('Google Drive: Deleting file $fileId');
      final token = await _getAccessToken();
      
      await _dio.delete(
        'https://www.googleapis.com/drive/v3/files/$fileId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      LogService.log('Google Drive: File deleted successfully from cloud');
      return true;
    } catch (e) {
      LogService.log('Google Drive Error: Failed to delete file: $e');
      return false;
    }
  }

  // ── SharedPreferences Settings Backup ──────────────────────────────────────

  Future<void> backupPreferences(Map<String, dynamic> prefs) async {
    try {
      LogService.log('Google Drive: Backing up user preferences to Tether/tether_preferences.json');
      final token = await _getAccessToken();
      final parentId = await _getOrCreateFolder(token, 'Tether');
      
      // Look for existing backup file in Tether folder
      final searchResponse = await _dio.get(
        'https://www.googleapis.com/drive/v3/files',
        queryParameters: {
          'q': "name = 'tether_preferences.json' and '$parentId' in parents and trashed = false",
          'fields': 'files(id)',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final files = searchResponse.data['files'] as List?;
      final jsonContent = jsonEncode(prefs);
      final jsonBytes = utf8.encode(jsonContent);

      if (files != null && files.isNotEmpty) {
        // Update existing file
        final fileId = files.first['id'] as String;
        await _dio.patch(
          'https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media',
          data: Stream.fromIterable([jsonBytes]),
          options: Options(headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Content-Length': jsonBytes.length.toString(),
          }),
        );
      } else {
        // Create new backup file
        final metadata = jsonEncode({
          'name': 'tether_preferences.json',
          'parents': [parentId],
        });

        const boundary = 'tether_boundary';
        final header = '\r\n--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: application/json\r\n\r\n';
        const footer = '\r\n--$boundary--\r\n';

        final bodyBytes = [
          ...utf8.encode(header),
          ...jsonBytes,
          ...utf8.encode(footer),
        ];

        await _dio.post(
          'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
          data: Stream.fromIterable([bodyBytes]),
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'multipart/related; boundary=$boundary',
              'Content-Length': bodyBytes.length.toString(),
            },
          ),
        );
      }
      LogService.log('Google Drive: User preferences backed up successfully');
    } catch (e) {
      LogService.log('Google Drive Error: Preferences backup failed: $e');
    }
  }

  Future<Map<String, dynamic>?> restorePreferences() async {
    try {
      LogService.log('Google Drive: Restoring user preferences from Tether/tether_preferences.json');
      final token = await _getAccessToken();
      final parentId = await _getOrCreateFolder(token, 'Tether');

      final searchResponse = await _dio.get(
        'https://www.googleapis.com/drive/v3/files',
        queryParameters: {
          'q': "name = 'tether_preferences.json' and '$parentId' in parents and trashed = false",
          'fields': 'files(id)',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final files = searchResponse.data['files'] as List?;
      if (files != null && files.isNotEmpty) {
        final fileId = files.first['id'] as String;
        final downloadResponse = await _dio.get(
          'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
            responseType: ResponseType.json,
          ),
        );
        LogService.log('Google Drive: Preferences restored successfully');
        return downloadResponse.data as Map<String, dynamic>?;
      }
    } catch (e) {
      LogService.log('Google Drive Error: Preferences restore failed: $e');
    }
    return null;
  }

  Future<void> backupKeyBackup(Map<String, dynamic> keyData) async {
    try {
      LogService.log('Google Drive: Backing up encrypted E2EE key payload');
      final token = await _getAccessToken();
      final parentId = await _getOrCreateFolder(token, 'Tether');
      
      final searchResponse = await _dio.get(
        'https://www.googleapis.com/drive/v3/files',
        queryParameters: {
          'q': "name = 'tether_key_backup.json' and '$parentId' in parents and trashed = false",
          'fields': 'files(id)',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final files = searchResponse.data['files'] as List?;
      final jsonContent = jsonEncode(keyData);
      final jsonBytes = utf8.encode(jsonContent);

      if (files != null && files.isNotEmpty) {
        final fileId = files.first['id'] as String;
        await _dio.patch(
          'https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media',
          data: Stream.fromIterable([jsonBytes]),
          options: Options(headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Content-Length': jsonBytes.length.toString(),
          }),
        );
      } else {
        final metadata = jsonEncode({
          'name': 'tether_key_backup.json',
          'parents': [parentId],
        });

        const boundary = 'tether_boundary';
        final header = '\r\n--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: application/json\r\n\r\n';
        const footer = '\r\n--$boundary--\r\n';

        final bodyBytes = [
          ...utf8.encode(header),
          ...jsonBytes,
          ...utf8.encode(footer),
        ];

        await _dio.post(
          'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
          data: Stream.fromIterable([bodyBytes]),
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'multipart/related; boundary=$boundary',
              'Content-Length': bodyBytes.length.toString(),
            },
          ),
        );
      }
      LogService.log('Google Drive: E2EE Key backup completed');
    } catch (e) {
      LogService.log('Google Drive Error: E2EE Key backup failed: $e');
    }
  }

  Future<Map<String, dynamic>?> restoreKeyBackup() async {
    try {
      LogService.log('Google Drive: Checking for E2EE key backup');
      final token = await _getAccessToken();
      final parentId = await _getOrCreateFolder(token, 'Tether');

      final searchResponse = await _dio.get(
        'https://www.googleapis.com/drive/v3/files',
        queryParameters: {
          'q': "name = 'tether_key_backup.json' and '$parentId' in parents and trashed = false",
          'fields': 'files(id)',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final files = searchResponse.data['files'] as List?;
      if (files != null && files.isNotEmpty) {
        final fileId = files.first['id'] as String;
        final downloadResponse = await _dio.get(
          'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
            responseType: ResponseType.json,
          ),
        );
        LogService.log('Google Drive: E2EE Key backup found and loaded');
        return downloadResponse.data as Map<String, dynamic>?;
      }
    } catch (e) {
      LogService.log('Google Drive Error: E2EE Key restore failed: $e');
    }
    return null;
  }
}
