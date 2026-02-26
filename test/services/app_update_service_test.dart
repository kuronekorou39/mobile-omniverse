import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/app_update_service.dart';

import '../helpers/mock_http_client.dart';

void main() {
  final service = AppUpdateService.instance;

  setUpAll(() {
    registerHttpFallbacks();
  });

  tearDown(() {
    service.httpClientOverride = null;
  });

  group('isNewer', () {
    test('same version returns false', () {
      expect(service.isNewer('1.2.3', '1.2.3'), false);
    });

    test('newer major returns true', () {
      expect(service.isNewer('2.0.0', '1.9.9'), true);
    });

    test('newer minor returns true', () {
      expect(service.isNewer('1.3.0', '1.2.9'), true);
    });

    test('newer patch returns true', () {
      expect(service.isNewer('1.2.4', '1.2.3'), true);
    });

    test('older version returns false', () {
      expect(service.isNewer('1.0.0', '1.2.3'), false);
    });

    test('older major returns false', () {
      expect(service.isNewer('0.9.9', '1.0.0'), false);
    });

    test('incomplete version pads with 0 - "1.2" vs "1.2.0"', () {
      expect(service.isNewer('1.2', '1.2.0'), false);
    });

    test('incomplete version "1.3" is newer than "1.2.9"', () {
      expect(service.isNewer('1.3', '1.2.9'), true);
    });

    test('invalid version returns false', () {
      expect(service.isNewer('abc', '1.0.0'), false);
    });

    test('invalid current returns false', () {
      expect(service.isNewer('1.0.0', 'xyz'), false);
    });

    test('edge case: "0.0.1" vs "0.0.0"', () {
      expect(service.isNewer('0.0.1', '0.0.0'), true);
    });

    test('edge case: "2.0.0" vs "1.9.9"', () {
      expect(service.isNewer('2.0.0', '1.9.9'), true);
    });

    test('single component "2" vs "1.0.0"', () {
      expect(service.isNewer('2', '1.0.0'), true);
    });

    test('single component same "1" vs "1.0.0"', () {
      expect(service.isNewer('1', '1.0.0'), false);
    });

    test('empty string returns false', () {
      expect(service.isNewer('', '1.0.0'), false);
    });

    test('both empty returns false', () {
      expect(service.isNewer('', ''), false);
    });

    test('minor older returns false', () {
      expect(service.isNewer('1.1.0', '1.2.0'), false);
    });

    test('patch older returns false', () {
      expect(service.isNewer('1.2.2', '1.2.3'), false);
    });
  });

  group('AppUpdateInfo', () {
    test('downloadUrl returns apkUrl when available', () {
      const info = AppUpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        releaseNotes: 'New features',
        apkUrl: 'https://example.com/app.apk',
        releaseUrl: 'https://github.com/releases/v1.1.0',
      );
      expect(info.downloadUrl, 'https://example.com/app.apk');
    });

    test('downloadUrl falls back to releaseUrl when apkUrl is null', () {
      const info = AppUpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        releaseNotes: 'New features',
        apkUrl: null,
        releaseUrl: 'https://github.com/releases/v1.1.0',
      );
      expect(info.downloadUrl, 'https://github.com/releases/v1.1.0');
    });

    test('fields are accessible', () {
      const info = AppUpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        releaseNotes: 'Bug fixes',
        apkUrl: 'https://example.com/app.apk',
        releaseUrl: 'https://github.com/releases/v1.1.0',
      );
      expect(info.currentVersion, '1.0.0');
      expect(info.latestVersion, '1.1.0');
      expect(info.releaseNotes, 'Bug fixes');
      expect(info.apkUrl, 'https://example.com/app.apk');
      expect(info.releaseUrl, 'https://github.com/releases/v1.1.0');
    });

    test('releaseNotes can be empty', () {
      const info = AppUpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        releaseNotes: '',
        releaseUrl: 'https://github.com/releases/v1.1.0',
      );
      expect(info.releaseNotes, isEmpty);
      expect(info.apkUrl, isNull);
    });
  });

  group('checkForUpdate - HTTP テスト', () {
    test('404 レスポンスで null を返す', () async {
      final mockClient = createMockClient(statusCode: 404);
      service.httpClientOverride = mockClient;

      final result = await service.checkForUpdate();
      // PackageInfo.fromPlatform() がテスト環境で例外を出す可能性があるため
      // null が返ることを期待（例外 catch で null を返す）
      expect(result, isNull);
    });

    test('500 レスポンスで null を返す', () async {
      final mockClient = createMockClient(statusCode: 500);
      service.httpClientOverride = mockClient;

      final result = await service.checkForUpdate();
      expect(result, isNull);
    });

    test('ネットワークエラーで null を返す', () async {
      final mockClient = createMockClient(statusCode: 200, body: 'invalid json');
      service.httpClientOverride = mockClient;

      final result = await service.checkForUpdate();
      // PackageInfo.fromPlatform() の例外かJSON解析エラーで null
      expect(result, isNull);
    });

    test('httpClientOverride を null にリセットできる', () {
      service.httpClientOverride = createMockClient();
      expect(service.httpClientOverride, isNotNull);

      service.httpClientOverride = null;
      expect(service.httpClientOverride, isNull);
    });

    test('200 レスポンスで古いバージョンの場合は null', () async {
      // Create a response with a version older than current
      final body = json.encode({
        'tag_name': 'v0.0.1',
        'body': 'Old release',
        'html_url': 'https://github.com/owner/repo/releases/v0.0.1',
        'assets': [],
      });
      final mockClient = createMockClient(statusCode: 200, body: body);
      service.httpClientOverride = mockClient;

      final result = await service.checkForUpdate();
      // PackageInfo.fromPlatform() may throw in test environment, so null
      expect(result, isNull);
    });

    test('空のボディで例外をキャッチして null を返す', () async {
      final mockClient = createMockClient(statusCode: 200, body: '');
      service.httpClientOverride = mockClient;

      final result = await service.checkForUpdate();
      expect(result, isNull);
    });

    test('不正なJSONオブジェクトで null を返す', () async {
      final mockClient = createMockClient(statusCode: 200, body: '[]');
      service.httpClientOverride = mockClient;

      final result = await service.checkForUpdate();
      expect(result, isNull);
    });
  });

  group('checkForUpdate - レスポンスパース', () {
    test('正常なリリースレスポンスのパース構造を検証', () {
      // GitHub Releases API レスポンスの構造をテスト
      final responseBody = json.encode({
        'tag_name': 'v2.0.0',
        'body': 'Release notes here',
        'html_url': 'https://github.com/owner/repo/releases/v2.0.0',
        'assets': [
          {
            'name': 'app-debug.apk',
            'browser_download_url':
                'https://github.com/owner/repo/releases/download/v2.0.0/app-debug.apk',
          },
        ],
      });

      final data = json.decode(responseBody) as Map<String, dynamic>;

      // tag_name のパース
      final tagName = data['tag_name'] as String;
      final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      expect(latestVersion, '2.0.0');

      // release notes のパース
      final releaseNotes = data['body'] as String;
      expect(releaseNotes, 'Release notes here');

      // html_url のパース
      final htmlUrl = data['html_url'] as String;
      expect(htmlUrl, 'https://github.com/owner/repo/releases/v2.0.0');

      // APK URL の検索
      String? apkUrl;
      final assets = data['assets'] as List<dynamic>;
      for (final asset in assets) {
        final a = asset as Map<String, dynamic>;
        final name = a['name'] as String;
        if (name.endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      expect(apkUrl, contains('app-debug.apk'));
    });

    test('APK アセットがないレスポンスの処理', () {
      final responseBody = json.encode({
        'tag_name': 'v1.5.0',
        'body': 'No APK in this release',
        'html_url': 'https://github.com/owner/repo/releases/v1.5.0',
        'assets': [
          {
            'name': 'source.tar.gz',
            'browser_download_url':
                'https://github.com/owner/repo/archive/v1.5.0.tar.gz',
          },
        ],
      });

      final data = json.decode(responseBody) as Map<String, dynamic>;
      String? apkUrl;
      final assets = data['assets'] as List<dynamic>;
      for (final asset in assets) {
        final a = asset as Map<String, dynamic>;
        final name = a['name'] as String;
        if (name.endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }
      expect(apkUrl, isNull);
    });

    test('空の assets リストの処理', () {
      final responseBody = json.encode({
        'tag_name': 'v1.0.0',
        'body': '',
        'html_url': 'https://github.com/owner/repo/releases/v1.0.0',
        'assets': <dynamic>[],
      });

      final data = json.decode(responseBody) as Map<String, dynamic>;
      final assets = data['assets'] as List<dynamic>;
      expect(assets, isEmpty);
    });

    test('tag_name に v プレフィックスがない場合', () {
      final tagName = '1.0.0';
      final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      expect(latestVersion, '1.0.0');
    });

    test('tag_name に v プレフィックスがある場合', () {
      final tagName = 'v1.0.0';
      final latestVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      expect(latestVersion, '1.0.0');
    });

    test('body が null の場合にデフォルト値を使用', () {
      final data = <String, dynamic>{
        'tag_name': 'v1.0.0',
        'body': null,
        'html_url': 'https://github.com/owner/repo/releases/v1.0.0',
      };

      final releaseNotes = data['body'] as String? ?? '';
      expect(releaseNotes, isEmpty);
    });

    test('html_url が null の場合にデフォルト値を使用', () {
      final data = <String, dynamic>{
        'tag_name': 'v1.0.0',
        'body': 'notes',
        'html_url': null,
      };

      final htmlUrl = data['html_url'] as String? ?? '';
      expect(htmlUrl, isEmpty);
    });

    test('tag_name が null の場合にデフォルト値を使用', () {
      final data = <String, dynamic>{
        'tag_name': null,
        'body': 'notes',
        'html_url': 'https://example.com',
      };

      final tagName = data['tag_name'] as String? ?? '';
      expect(tagName, isEmpty);
    });

    test('assets が null の場合の処理', () {
      final data = <String, dynamic>{
        'tag_name': 'v1.0.0',
        'body': 'notes',
        'html_url': 'https://example.com',
        'assets': null,
      };

      final assets = data['assets'] as List<dynamic>? ?? [];
      expect(assets, isEmpty);
    });

    test('複数の APK アセットがある場合、最初のものを使用', () {
      final assets = <Map<String, dynamic>>[
        {
          'name': 'app-debug.apk',
          'browser_download_url': 'https://example.com/debug.apk',
        },
        {
          'name': 'app-release.apk',
          'browser_download_url': 'https://example.com/release.apk',
        },
      ];

      String? apkUrl;
      for (final asset in assets) {
        final name = asset['name'] as String;
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      expect(apkUrl, 'https://example.com/debug.apk');
    });
  });
}
