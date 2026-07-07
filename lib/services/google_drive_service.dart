import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../config/google_scopes.dart';
import 'auth_service.dart';
import 'log_service.dart';

class GoogleDriveService {
  final Dio _dio = Dio();
  final AuthService _auth = AuthService();

  GoogleDriveService() {
    // The 50-minute TTL is a conservative guess, not an authoritative expiry
    // (the plugin doesn't expose one). If Google invalidates a token early
    // (e.g. revoked externally) a call can still 401 before the TTL is up.
    // Evict the cache on any 401 so the *next* call fetches a fresh token
    // instead of repeating the same stale one for up to 50 more minutes.
    // This doesn't retry the failing call itself — callers still see the
    // exception — but it self-heals immediately rather than on a timer.
    _dio.interceptors.add(InterceptorsWrapper(onError: (error, handler) {
      final status = error.response?.statusCode;
      if (status == 401) {
        LogService.log('Google Drive: Got 401, evicting cached access token');
        invalidateCachedAccessToken();
      }
      // DioException's default toString() ("bad syntax or cannot be
      // fulfilled") is just the generic HTTP 403 spec text, not Google's
      // actual reason — the real cause (insufficientPermissions,
      // storageQuotaExceeded, notFound, etc.) is in the JSON response body.
      // Log it so the next failure is diagnosable instead of generic.
      if (status != null && status >= 400) {
        LogService.log('Google Drive: HTTP $status response body: ${error.response?.data}');
      }
      handler.next(error);
    }));
  }

  // Static, not instance-level: GoogleDriveService() is constructed fresh at
  // nearly every call site, so an instance field would never actually cache
  // anything (same lesson as AuthService._cachedGoogleUser).
  //
  // Google's own access tokens for these scopes last ~1h, but the plugin's
  // GoogleSignInClientAuthorization doesn't surface an expiry — 50 minutes
  // is a conservative TTL safely under that.
  static String? _cachedAccessToken;
  static DateTime? _cachedTokenObtainedAt;
  static Future<String>? _tokenFuture;
  static const _tokenTtl = Duration(minutes: 50);

  // Only ever checks the cached authorization silently. Android requires
  // authorizeScopes() (the interactive grant) to be triggered by a real user
  // tap, so it must never be called from this background path — doing so
  // was the cause of the Google consent screen popping up repeatedly.
  //
  // This is also the app's only scope-validity check — there's no separate
  // proactive/periodic scan for missing scopes. If a future update adds a
  // new required scope, a signed-in user just won't have it cached yet;
  // the first Drive call that actually needs it lands here, finds it
  // missing, and signs them out so the normal login flow re-requests the
  // full current scope set. That's lazy/reactive rather than checked on
  // every app open, matching how most Google Sign-In apps behave.
  Future<String> _getAccessToken() async {
    final cached = _cachedAccessToken;
    final obtainedAt = _cachedTokenObtainedAt;
    if (cached != null && obtainedAt != null && DateTime.now().difference(obtainedAt) < _tokenTtl) {
      return cached;
    }
    return _tokenFuture ??= _fetchAccessToken().whenComplete(() => _tokenFuture = null);
  }

  // authorizationForScopes() is a separate Play Services round trip from
  // AuthService.getGoogleUser()'s cached lightweight-auth check — calling it
  // fresh on every single Drive operation (uploads, downloads, folder
  // lookups, ...) was still triggering a brief system UI transition per
  // call, even though the account itself was already cached. Caching the
  // resulting token here (not just the account) collapses that down to at
  // most once per _tokenTtl, regardless of how many Drive operations happen
  // in between.
  Future<String> _fetchAccessToken() async {
    LogService.log('Google Drive: Obtaining access token');
    final googleUser = await _auth.getGoogleUser();
    if (googleUser == null) {
      LogService.log('Google Drive Error: Lightweight authentication returned null user');
      throw Exception('Google Sign-In user is not available.');
    }

    final authorization = await googleUser.authorizationClient.authorizationForScopes(GoogleScopes.drive);
    final token = authorization?.accessToken;
    if (token == null) {
      LogService.log('Google Drive Error: Drive scopes not authorized. Signing out to force re-consent on next login.');
      await _auth.signOut();
      throw Exception('Google Drive access not authorized. Please sign in again.');
    }

    _cachedAccessToken = token;
    _cachedTokenObtainedAt = DateTime.now();
    LogService.log('Google Drive: Successfully retrieved cached access token silently');
    return token;
  }

  /// Call after signing out, or after any Drive call fails with a 401, so
  /// the next request re-fetches rather than retrying a stale/invalid token.
  static void invalidateCachedAccessToken() {
    _cachedAccessToken = null;
    _cachedTokenObtainedAt = null;
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

  // ── Generic named-file helpers (backup pipeline) ────────────────────────
  //
  // Unlike uploadSnap/backupKeyBackup above (each hardcoded to one
  // filename), these operate on an arbitrary filename
  // within the Tether folder, since the backup pipeline needs to find,
  // write, rename, and delete files by the generation names in
  // BackupConfig (latest_backup, backup_gen1/2/3, etc).

  Future<String?> findFileIdByName(String fileName) async {
    final token = await _getAccessToken();
    final parentId = await _getOrCreateFolder(token, 'Tether');
    return _findFileIdInFolder(token, parentId, fileName);
  }

  Future<String?> _findFileIdInFolder(
      String token, String parentId, String fileName) async {
    final response = await _dio.get(
      'https://www.googleapis.com/drive/v3/files',
      queryParameters: {
        'q': "name = '$fileName' and '$parentId' in parents and trashed = false",
        'fields': 'files(id)',
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final files = response.data['files'] as List?;
    if (files == null || files.isEmpty) return null;
    return files.first['id'] as String;
  }

  /// Uploads [bytes] as [fileName] in the Tether folder, replacing it if a
  /// file with that name already exists.
  Future<void> uploadOrReplaceBytes(String fileName, Uint8List bytes,
      {String mimeType = 'application/octet-stream'}) async {
    final token = await _getAccessToken();
    final parentId = await _getOrCreateFolder(token, 'Tether');
    final existingId = await _findFileIdInFolder(token, parentId, fileName);

    if (existingId != null) {
      await _dio.patch(
        'https://www.googleapis.com/upload/drive/v3/files/$existingId?uploadType=media',
        data: Stream.fromIterable([bytes]),
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': mimeType,
          'Content-Length': bytes.length.toString(),
        }),
      );
      return;
    }

    final metadata = jsonEncode({'name': fileName, 'parents': [parentId]});
    const boundary = 'tether_boundary';
    final header =
        '\r\n--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n--$boundary\r\nContent-Type: $mimeType\r\n\r\n';
    const footer = '\r\n--$boundary--\r\n';
    final bodyBytes = [
      ...utf8.encode(header),
      ...bytes,
      ...utf8.encode(footer),
    ];
    await _dio.post(
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
      data: Stream.fromIterable([bodyBytes]),
      options: Options(headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'multipart/related; boundary=$boundary',
        'Content-Length': bodyBytes.length.toString(),
      }),
    );
  }

  /// Downloads [fileName] from the Tether folder, or null if it doesn't exist.
  Future<Uint8List?> downloadBytesByName(String fileName) async {
    final token = await _getAccessToken();
    final parentId = await _getOrCreateFolder(token, 'Tether');
    final fileId = await _findFileIdInFolder(token, parentId, fileName);
    if (fileId == null) return null;

    final response = await _dio.get<List<int>>(
      'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.bytes,
      ),
    );
    return Uint8List.fromList(response.data ?? []);
  }

  /// Renames [fileName] to [newName] within the Tether folder. If
  /// [fileName] doesn't exist, this is a no-op (returns false).
  ///
  /// Unlike a real filesystem, Drive allows multiple files with the same
  /// name in one folder — if a prior rotation run was interrupted partway,
  /// [newName] might already be occupied by a stale file. Clear it first
  /// so a retry can never produce ambiguous duplicate-named files.
  Future<bool> renameFileByName(String fileName, String newName) async {
    final token = await _getAccessToken();
    final parentId = await _getOrCreateFolder(token, 'Tether');
    final fileId = await _findFileIdInFolder(token, parentId, fileName);
    if (fileId == null) return false;

    final staleId = await _findFileIdInFolder(token, parentId, newName);
    if (staleId != null) {
      await _dio.delete(
        'https://www.googleapis.com/drive/v3/files/$staleId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    }

    await _dio.patch(
      'https://www.googleapis.com/drive/v3/files/$fileId',
      data: {'name': newName},
      options: Options(headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }),
    );
    return true;
  }

  /// Deletes [fileName] within the Tether folder if it exists.
  Future<bool> deleteFileByName(String fileName) async {
    final token = await _getAccessToken();
    final parentId = await _getOrCreateFolder(token, 'Tether');
    final fileId = await _findFileIdInFolder(token, parentId, fileName);
    if (fileId == null) return false;

    await _dio.delete(
      'https://www.googleapis.com/drive/v3/files/$fileId',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return true;
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
