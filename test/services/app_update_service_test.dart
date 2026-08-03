import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/app_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/mock_http_client.dart';

void main() {
  final service = AppUpdateService.instance;

  setUpAll(() {
    registerHttpFallbacks();
    PackageInfo.setMockInitialValues(
      appName: 'OmniVerse',
      packageName: 'com.rou39.omniverse',
      version: '1.14.0',
      buildNumber: '350',
      buildSignature: '',
    );
  });

  tearDown(() {
    service.httpClientOverride = null;
    service.isIOSOverride = null;
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
      expect(
        info.downloadUrl,
        'https://rou39.com/omniverse/OmniVerse-v1.1.0.apk',
      );
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
      final mockClient = createMockClient(
        statusCode: 200,
        body: 'invalid json',
      );
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
      final data = <String, dynamic>{'version': null, 'release_notes': 'notes'};

      final version = data['version'] as String? ?? '';
      expect(version, isEmpty);
    });

    test('release_notes が null の場合にデフォルト値', () {
      final data = <String, dynamic>{'version': '1.0.0', 'release_notes': null};

      final notes = data['release_notes'] as String? ?? '';
      expect(notes, isEmpty);
    });
  });

  group('checkForUpdate - iOS (App Store 照会)', () {
    // charset を明示しないと http.Response が Latin-1 として読み、
    // 日本語のリリースノートで落ちる
    MockHttpClient jsonClient(String body) => createMockClient(
      body: body,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

    String lookupBody({
      required String version,
      String notes = '',
      String url = 'https://apps.apple.com/jp/app/omniverse/id6763051731?uo=4',
    }) => json.encode({
      'resultCount': 1,
      'results': [
        {'version': version, 'releaseNotes': notes, 'trackViewUrl': url},
      ],
    });

    test('ストアが新しければ storeUrl 付きで返す', () async {
      service.isIOSOverride = true;
      service.httpClientOverride = jsonClient(
        lookupBody(version: '1.15.0', notes: '不具合を修正しました'),
      );

      final result = await service.checkForUpdate();

      expect(result, isNotNull);
      expect(result!.latestVersion, '1.15.0');
      expect(result.currentVersion, '1.14.0');
      expect(result.releaseNotes, '不具合を修正しました');
      expect(result.isAppStore, true);
      expect(
        result.downloadUrl,
        'https://apps.apple.com/jp/app/omniverse/id6763051731?uo=4',
      );
      // APK の導線は iOS では出てはいけない
      expect(result.apkUrl, isNull);
    });

    test('ストアが同じバージョンなら null', () async {
      service.isIOSOverride = true;
      service.httpClientOverride = jsonClient(lookupBody(version: '1.14.0'));

      expect(await service.checkForUpdate(), isNull);
    });

    test('ストアのほうが古ければ null', () async {
      service.isIOSOverride = true;
      service.httpClientOverride = jsonClient(lookupBody(version: '1.13.10'));

      expect(await service.checkForUpdate(), isNull);
    });

    // 公開直後は Apple の索引が追いつかず 0 件が返る。
    // ここで通知を出してしまうと、ストアに無いものを案内することになる。
    test('results が空なら更新なし扱い', () async {
      service.isIOSOverride = true;
      service.httpClientOverride = jsonClient(
        json.encode({'resultCount': 0, 'results': []}),
      );

      expect(await service.checkForUpdate(), isNull);
    });

    test('trackViewUrl が無ければ自前サイトに落ちる', () async {
      service.isIOSOverride = true;
      service.httpClientOverride = jsonClient(
        json.encode({
          'resultCount': 1,
          'results': [
            {'version': '1.15.0'},
          ],
        }),
      );

      final result = await service.checkForUpdate();

      expect(result, isNotNull);
      expect(result!.isAppStore, false);
      expect(result.downloadUrl, 'https://rou39.com/omniverse/');
    });

    test('Android 経路では storeUrl は付かない', () async {
      service.isIOSOverride = false;
      service.httpClientOverride = jsonClient(
        json.encode({
          'version': '1.15.0',
          'release_notes': 'バグ修正',
          'apk_url': 'https://rou39.com/omniverse/OmniVerse-v1.15.0.apk',
        }),
      );

      final result = await service.checkForUpdate();

      expect(result, isNotNull);
      expect(result!.isAppStore, false);
      expect(result.storeUrl, isNull);
      expect(
        result.downloadUrl,
        'https://rou39.com/omniverse/OmniVerse-v1.15.0.apk',
      );
    });
  });
}
