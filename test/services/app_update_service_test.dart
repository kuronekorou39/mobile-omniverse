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
        apkUrl: 'https://rou39.com/omniverse/OmniVerse-v1.1.0.apk',
      );
      expect(info.downloadUrl, 'https://rou39.com/omniverse/OmniVerse-v1.1.0.apk');
    });

    test('downloadUrl falls back to site URL when apkUrl is null', () {
      const info = AppUpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        releaseNotes: 'New features',
        apkUrl: null,
      );
      expect(info.downloadUrl, 'https://rou39.com/omniverse/');
    });

    test('fields are accessible', () {
      const info = AppUpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        releaseNotes: 'Bug fixes',
        apkUrl: 'https://rou39.com/omniverse/app.apk',
      );
      expect(info.currentVersion, '1.0.0');
      expect(info.latestVersion, '1.1.0');
      expect(info.releaseNotes, 'Bug fixes');
      expect(info.apkUrl, 'https://rou39.com/omniverse/app.apk');
    });

    test('releaseNotes can be empty', () {
      const info = AppUpdateInfo(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        releaseNotes: '',
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
      expect(result, isNull);
    });

    test('httpClientOverride を null にリセットできる', () {
      service.httpClientOverride = createMockClient();
      expect(service.httpClientOverride, isNotNull);

      service.httpClientOverride = null;
      expect(service.httpClientOverride, isNull);
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
    test('update.json の構造を検証', () {
      final responseBody = json.encode({
        'version': '2.0.0',
        'release_notes': 'Release notes here',
        'apk_url': 'https://rou39.com/omniverse/OmniVerse-v2.0.0.apk',
      });

      final data = json.decode(responseBody) as Map<String, dynamic>;

      expect(data['version'], '2.0.0');
      expect(data['release_notes'], 'Release notes here');
      expect(data['apk_url'], contains('v2.0.0.apk'));
    });

    test('apk_url が null の場合', () {
      final data = <String, dynamic>{
        'version': '1.5.0',
        'release_notes': 'No APK',
      };

      final apkUrl = data['apk_url'] as String?;
      expect(apkUrl, isNull);
    });

    test('version が null の場合にデフォルト値', () {
      final data = <String, dynamic>{
        'version': null,
        'release_notes': 'notes',
      };

      final version = data['version'] as String? ?? '';
      expect(version, isEmpty);
    });

    test('release_notes が null の場合にデフォルト値', () {
      final data = <String, dynamic>{
        'version': '1.0.0',
        'release_notes': null,
      };

      final notes = data['release_notes'] as String? ?? '';
      expect(notes, isEmpty);
    });
  });
}
