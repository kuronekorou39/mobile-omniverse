import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// アプリ更新チェックサービス
///
/// 配信元がプラットフォームで違うので、見に行く先も分ける。
///
/// - Android: 自前ホスト (rou39.com) の JSON。APK を直接ダウンロードさせる
/// - iOS: App Store の公開バージョンを Apple の照会 API から取り、ストアへ送る
///
/// iOS で自前 JSON を使わないのは審査の待ち時間があるため。提出時に JSON を
/// 上げると審査待ちの数日間「ストアに無いバージョン」を通知してしまい、承認後に
/// 上げると Android と更新タイミングを二重管理することになる。照会 API は
/// 公開済みのものしか返さないので、この食い違いが原理的に起きない。
///
/// JSON フォーマット (Android):
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

  /// テストから iOS 経路を通すための差し替え口
  @visibleForTesting
  bool? isIOSOverride;

  static const _updateJsonUrl = 'https://rou39.com/omniverse/update.json';
  static const _lookupUrl = 'https://itunes.apple.com/lookup';
  static const _bundleId = 'com.rou39.omniverse';

  /// 日本のストアにしか出していないので、既定の US を見に行かないよう明示する
  static const _storeCountry = 'jp';

  bool get _isIOS => isIOSOverride ?? Platform.isIOS;

  http.Client get _client => httpClientOverride ?? http.Client();

  static const _headers = {
    'User-Agent': 'OmniVerse-App',
    'Cache-Control': 'no-cache',
  };

  /// 最新リリース情報を取得し、現在のバージョンより新しい場合に返す
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      debugPrint('[AppUpdate] Current version: $currentVersion');

      return _isIOS
          ? await _checkAppStore(currentVersion)
          : await _checkSelfHosted(currentVersion);
    } catch (e) {
      debugPrint('[AppUpdate] Error checking for update: $e');
      return null;
    }
  }

  /// Android: 自前ホストの update.json を見る
  Future<AppUpdateInfo?> _checkSelfHosted(String currentVersion) async {
    final response = await _client.get(
      Uri.parse(_updateJsonUrl),
      headers: _headers,
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
  }

  /// iOS: App Store で公開中のバージョンを照会する
  Future<AppUpdateInfo?> _checkAppStore(String currentVersion) async {
    final uri = Uri.parse(_lookupUrl).replace(
      queryParameters: {'bundleId': _bundleId, 'country': _storeCountry},
    );
    final response = await _client.get(uri, headers: _headers);

    if (response.statusCode != 200) {
      debugPrint('[AppUpdate] Lookup failed: ${response.statusCode}');
      return null;
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? const [];

    // 公開直後は Apple 側の索引が追いつかず 0 件が返る。更新なしとして扱い、
    // 存在しない更新を通知しないほうに倒す。
    if (results.isEmpty) {
      debugPrint('[AppUpdate] App Store にまだ反映されていない');
      return null;
    }

    final entry = results.first as Map<String, dynamic>;
    final latestVersion = entry['version'] as String? ?? '';

    debugPrint('[AppUpdate] App Store version: $latestVersion');

    if (!isNewer(latestVersion, currentVersion)) {
      debugPrint('[AppUpdate] Already up to date');
      return null;
    }

    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseNotes: entry['releaseNotes'] as String? ?? '',
      storeUrl: entry['trackViewUrl'] as String?,
    );
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
    this.storeUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;

  /// Android の自前配布 APK
  final String? apkUrl;

  /// iOS の App Store ページ
  final String? storeUrl;

  /// App Store 経由の更新か。導線の見せ方を変えるのに使う
  bool get isAppStore => storeUrl != null;

  String get downloadUrl =>
      storeUrl ?? apkUrl ?? 'https://rou39.com/omniverse/';
}
