import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/models/sns_service.dart';

import '../helpers/test_data.dart';

void main() {
  group('BlueskyCredentials', () {
    test('toJson / fromJson 往復', () {
      const creds = BlueskyCredentials(
        accessJwt: 'jwt_access',
        refreshJwt: 'jwt_refresh',
        did: 'did:plc:abc123',
        handle: 'user.bsky.social',
        pdsUrl: 'https://bsky.social',
      );

      final json = creds.toJson();
      final restored = BlueskyCredentials.fromJson(json);

      expect(restored.accessJwt, 'jwt_access');
      expect(restored.refreshJwt, 'jwt_refresh');
      expect(restored.did, 'did:plc:abc123');
      expect(restored.handle, 'user.bsky.social');
      expect(restored.pdsUrl, 'https://bsky.social');
    });

    test('デフォルト pdsUrl', () {
      const creds = BlueskyCredentials(
        accessJwt: 'a',
        refreshJwt: 'r',
        did: 'did:plc:x',
        handle: 'test',
      );

      expect(creds.pdsUrl, 'https://bsky.social');
    });

    test('fromJson で pdsUrl が null の場合デフォルト値', () {
      final creds = BlueskyCredentials.fromJson({
        'accessJwt': 'a',
        'refreshJwt': 'r',
        'did': 'did:plc:x',
        'handle': 'test',
      });

      expect(creds.pdsUrl, 'https://bsky.social');
    });

    test('copyWith で accessJwt を更新', () {
      const creds = BlueskyCredentials(
        accessJwt: 'old',
        refreshJwt: 'refresh',
        did: 'did:plc:x',
        handle: 'test',
      );

      final updated = creds.copyWith(accessJwt: 'new');

      expect(updated.accessJwt, 'new');
      expect(updated.refreshJwt, 'refresh');
      expect(updated.did, 'did:plc:x');
    });

    test('copyWith で refreshJwt を更新', () {
      const creds = BlueskyCredentials(
        accessJwt: 'access',
        refreshJwt: 'old_refresh',
        did: 'did:plc:x',
        handle: 'test',
      );

      final updated = creds.copyWith(refreshJwt: 'new_refresh');

      expect(updated.accessJwt, 'access');
      expect(updated.refreshJwt, 'new_refresh');
    });

    test('copyWith 変更なし', () {
      const creds = BlueskyCredentials(
        accessJwt: 'a',
        refreshJwt: 'r',
        did: 'did:plc:x',
        handle: 'test',
      );

      final updated = creds.copyWith();

      expect(updated.accessJwt, 'a');
      expect(updated.refreshJwt, 'r');
    });
  });

  group('XCredentials', () {
    test('toJson / fromJson 往復', () {
      const creds = XCredentials(
        authToken: 'auth123',
        ct0: 'csrf456',
        allCookies: 'auth_token=auth123; ct0=csrf456',
      );

      final json = creds.toJson();
      final restored = XCredentials.fromJson(json);

      expect(restored.authToken, 'auth123');
      expect(restored.ct0, 'csrf456');
      expect(restored.allCookies, 'auth_token=auth123; ct0=csrf456');
    });

    test('allCookies が空の場合のデフォルト値', () {
      final creds = XCredentials.fromJson({
        'authToken': 'auth',
        'ct0': 'ct0val',
      });

      expect(creds.allCookies, '');
    });

    group('cookieHeader', () {
      test('allCookies がある場合はそれを使用', () {
        const creds = XCredentials(
          authToken: 'auth',
          ct0: 'ct0',
          allCookies: 'full_cookie_string',
        );

        expect(creds.cookieHeader, 'full_cookie_string');
      });

      test('allCookies が空の場合は auth_token と ct0 で構築', () {
        const creds = XCredentials(
          authToken: 'myauth',
          ct0: 'myct0',
        );

        expect(creds.cookieHeader, 'auth_token=myauth; ct0=myct0');
      });
    });
  });

  group('Account', () {
    test('X Account の toJson / fromJson 往復', () {
      final account = makeXAccount(
        id: 'x_1',
        displayName: 'X User',
        handle: '@xuser',
        authToken: 'auth',
        ct0: 'ct0',
      );

      final json = account.toJson();
      final restored = Account.fromJson(json);

      expect(restored.id, 'x_1');
      expect(restored.service, SnsService.x);
      expect(restored.displayName, 'X User');
      expect(restored.handle, '@xuser');
      expect(restored.isEnabled, true);

      final creds = restored.xCredentials;
      expect(creds.authToken, 'auth');
      expect(creds.ct0, 'ct0');
    });

    test('Bluesky Account の toJson / fromJson 往復', () {
      final account = makeBlueskyAccount(
        id: 'bsky_1',
        displayName: 'Bluesky User',
        handle: '@bsky.test',
        accessJwt: 'jwt_a',
        refreshJwt: 'jwt_r',
        did: 'did:plc:test',
      );

      final json = account.toJson();
      final restored = Account.fromJson(json);

      expect(restored.id, 'bsky_1');
      expect(restored.service, SnsService.bluesky);
      expect(restored.displayName, 'Bluesky User');

      final creds = restored.blueskyCredentials;
      expect(creds.accessJwt, 'jwt_a');
      expect(creds.refreshJwt, 'jwt_r');
      expect(creds.did, 'did:plc:test');
    });

    test('credentials が JSON 文字列として保存される', () {
      final account = makeXAccount();
      final json = account.toJson();

      // credentials フィールドは JSON エンコードされた文字列
      expect(json['credentials'], isA<String>());
      final decoded = jsonDecode(json['credentials'] as String);
      expect(decoded, isA<Map<String, dynamic>>());
    });

    test('copyWith で credentials を更新', () {
      final account = makeXAccount(authToken: 'old');
      final newCreds = const XCredentials(authToken: 'new', ct0: 'new_ct0');
      final updated = account.copyWith(credentials: newCreds);

      expect(updated.xCredentials.authToken, 'new');
      expect(updated.id, account.id);
    });

    test('copyWith で isEnabled を更新', () {
      final account = makeXAccount(isEnabled: true);
      final updated = account.copyWith(isEnabled: false);

      expect(updated.isEnabled, false);
      expect(updated.id, account.id);
    });

    test('copyWith 変更なし', () {
      final account = makeXAccount();
      final updated = account.copyWith();

      expect(updated.id, account.id);
      expect(updated.isEnabled, account.isEnabled);
    });

    test('createdAt の保存・復元', () {
      final dt = DateTime(2024, 6, 15, 10, 30, 0);
      final account = Account(
        id: 'test',
        service: SnsService.x,
        displayName: 'Test',
        handle: '@test',
        credentials: const XCredentials(authToken: 'a', ct0: 'c'),
        createdAt: dt,
      );

      final json = account.toJson();
      final restored = Account.fromJson(json);

      expect(restored.createdAt, dt);
    });

    test('avatarUrl の保存・復元', () {
      final account = Account(
        id: 'test',
        service: SnsService.x,
        displayName: 'Test',
        handle: '@test',
        avatarUrl: 'https://example.com/avatar.jpg',
        credentials: const XCredentials(authToken: 'a', ct0: 'c'),
        createdAt: DateTime(2024),
      );

      final json = account.toJson();
      final restored = Account.fromJson(json);

      expect(restored.avatarUrl, 'https://example.com/avatar.jpg');
    });

    test('avatarUrl が null の場合', () {
      final account = makeXAccount();
      final json = account.toJson();
      final restored = Account.fromJson(json);

      expect(restored.avatarUrl, isNull);
    });
  });
}
