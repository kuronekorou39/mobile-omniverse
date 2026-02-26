import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// GitHub Releases ベースのアプリ更新チェックサービス
class AppUpdateService {
  AppUpdateService._();
  static final instance = AppUpdateService._();

  @visibleForTesting
  http.Client? httpClientOverride;

  static const _owner = 'kuronekorou39';
  static const _repo = 'mobile-omniverse';

  /// 最新リリース情報を取得し、現在のバージョンより新しい場合に返す
  /// 新しいバージョンがなければ null を返す
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      debugPrint('[AppUpdate] Current version: $currentVersion');

      final response = await (httpClientOverride ?? http.Client()).get(
        Uri.parse(
          'https://api.github.com/repos/$_owner/$_repo/releases/latest',
        ),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'OmniVerse-App',
        },
      );

      if (response.statusCode == 404) {
        debugPrint('[AppUpdate] No releases found');
        return null;
      }

      if (response.statusCode != 200) {
        debugPrint('[AppUpdate] GitHub API error: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      final releaseNotes = data['body'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? '';

      debugPrint('[AppUpdate] Latest release: $latestVersion');

      if (!isNewer(latestVersion, currentVersion)) {
        debugPrint('[AppUpdate] Already up to date');
        return null;
      }

      // APK アセット URL を探す
      String? apkUrl;
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final a = asset as Map<String, dynamic>;
        final name = a['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseNotes: releaseNotes,
        apkUrl: apkUrl,
        releaseUrl: htmlUrl,
      );
    } catch (e) {
      debugPrint('[AppUpdate] Error checking for update: $e');
      return null;
    }
  }

  /// semver 比較: version が current より新しいか
  @visibleForTesting
  bool isNewer(String version, String current) {
    try {
      final vParts = version.split('.').map(int.parse).toList();
      final cParts = current.split('.').map(int.parse).toList();

      // 足りない部分を 0 で補完
      while (vParts.length < 3) {
        vParts.add(0);
      }
      while (cParts.length < 3) {
        cParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (vParts[i] > cParts[i]) return true;
        if (vParts[i] < cParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    this.apkUrl,
    required this.releaseUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String? apkUrl;
  final String releaseUrl;

  /// ダウンロード用 URL (APK があればそれを、なければリリースページ)
  String get downloadUrl => apkUrl ?? releaseUrl;
}
