import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'log_service.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String? releaseNotes;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.releaseNotes,
  });
}

class UpdateService {
  static const _apiUrl =
      'https://api.github.com/repos/dwaipayanray95/tether/releases/latest';

  static Future<UpdateInfo?> checkForUpdate() async {
    LogService.log('Checking for app updates...');
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      final dio = Dio();
      dio.options.headers = {'Accept': 'application/vnd.github+json'};
      final response = await dio.get(_apiUrl);
      final data = response.data as Map<String, dynamic>;

      final tag = (data['tag_name'] as String).replaceFirst('v', '');
      final notes = data['body'] as String?;

      final assets = data['assets'] as List? ?? [];
      final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
            (a) => (a['name'] as String).endsWith('.apk'),
            orElse: () => {},
          );
      if (apkAsset.isEmpty) return null;

      final downloadUrl = apkAsset['browser_download_url'] as String;

      if (_isNewer(tag, current)) {
        LogService.log('Update AVAILABLE: $tag (current: $current)');
        return UpdateInfo(
            version: tag, downloadUrl: downloadUrl, releaseNotes: notes);
      }
      LogService.log('App is up to date ($current)');
      return null;
    } catch (e) {
      LogService.log('Error checking for update: $e');
      return null;
    }
  }

  static Future<String?> downloadAndInstall(
    String url,
    void Function(double progress) onProgress,
  ) async {
    LogService.log('Starting update download: $url');
    // Download to external cache so FileProvider can serve it
    final dirs = await getExternalCacheDirectories();
    final dir = dirs?.isNotEmpty == true
        ? dirs!.first
        : await getTemporaryDirectory();
    final path = '${dir.path}/tether-update.apk';

    final dio = Dio();
    await dio.download(
      url,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );

    final result = await OpenFile.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    LogService.log('Update installer result: ${result.type} - ${result.message}');

    // Return error message if installation failed, null if successful
    if (result.type != ResultType.done) {
      return result.message;
    }
    return null;
  }

  static bool _isNewer(String latest, String current) {
    try {
      final l = latest.split('.').map(int.parse).toList();
      final c = current.split('.').map(int.parse).toList();
      while (l.length < 3) {
        l.add(0);
      }
      while (c.length < 3) {
        c.add(0);
      }
      for (int i = 0; i < 3; i++) {
        if (l[i] > c[i]) return true;
        if (l[i] < c[i]) return false;
      }
    } catch (_) {}
    return false;
  }
}
