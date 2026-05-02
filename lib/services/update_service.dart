import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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
        return UpdateInfo(
            version: tag, downloadUrl: downloadUrl, releaseNotes: notes);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> downloadAndInstall(
    String url,
    void Function(double progress) onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/tether-update.apk';

    final dio = Dio();
    await dio.download(
      url,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );

    await OpenFile.open(path);
  }

  static bool _isNewer(String latest, String current) {
    try {
      final l = latest.split('.').map(int.parse).toList();
      final c = current.split('.').map(int.parse).toList();
      while (l.length < 3) { l.add(0); }
      while (c.length < 3) { c.add(0); }
      for (int i = 0; i < 3; i++) {
        if (l[i] > c[i]) return true;
        if (l[i] < c[i]) return false;
      }
    } catch (_) {}
    return false;
  }
}
