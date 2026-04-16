import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 自前ホスト (rou39.com) の JSON ベースのアプリ更新チェックサービス
///
/// JSON フォーマット:
/// {
///   "version": "1.13.6",
///   "release_notes": "変更内容",
///   "apk_url": "https://rou39.com/omniverse/OmniVerse-v1.13.6.apk"
/// }
class AppUpdateService {
  AppUpdateService._();
  static final instance = AppUpdateService._();

  @visibleForTesting
  http.Client? httpClientOverride;

  static const _updateJsonUrl = 'https://rou39.com/omniverse/update.json';

  /// 最新リリース情報を取得し、現在のバージョンより新しい場合に返す
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      debugPrint('[AppUpdate] Current version: $currentVersion');

      final response = await (httpClientOverride ?? http.Client()).get(
        Uri.parse(_updateJsonUrl),
        headers: {
          'User-Agent': 'OmniVerse-App',
          'Cache-Control': 'no-cache',
        },
      );

      if (response.statusCode != 200) {
        debugPrint('[AppUpdate] Update check failed: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final latestVersion = data['version'] as String? ?? '';
      final releaseNotes = data['release_notes'] as String? ?? '';
      final apkUrl = data['apk_url'] as String?;

      debugPrint('[AppUpdate] Latest release: $latestVersion');

      if (!isNewer(latestVersion, currentVersion)) {
        debugPrint('[AppUpdate] Already up to date');
        return null;
      }

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseNotes: releaseNotes,
        apkUrl: apkUrl,
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

      while (vParts.length < 3) vParts.add(0);
      while (cParts.length < 3) cParts.add(0);

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
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String? apkUrl;

  String get downloadUrl => apkUrl ?? 'https://rou39.com/omniverse/';
}
