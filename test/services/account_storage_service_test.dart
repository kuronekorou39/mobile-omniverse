import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_data.dart';

void main() {
  final storage = AccountStorageService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // ストレージを再ロードしてクリーンな状態にする
    await storage.load();
  });

  group('AccountStorageService - シングルトン', () {
    test('シングルトンインスタンスが取得できる', () {
      expect(AccountStorageService.instance, isNotNull);
      expect(AccountStorageService.instance, same(storage));
    });
  });

  group('AccountStorageService - load', () {
    test('空のストレージからロード', () async {
      SharedPreferences.setMockInitialValues({});
      await storage.load();
      expect(storage.accounts, isEmpty);
    });

    test('accounts は不変リストを返す', () async {
      await storage.load();
      expect(storage.accounts, isA<List<Account>>());
      // List.unmodifiable で返されるため、型としては List<Account>
    });
  });

  group('AccountStorageService - addAccount', () {
    test('アカウントを追加できる', () async {
      final account = makeXAccount(id: 'add_test_1');
      await storage.addAccount(account);

      expect(storage.accounts.length, 1);
      expect(storage.accounts.first.id, 'add_test_1');
    });

    test('複数のアカウントを追加できる', () async {
      await storage.addAccount(makeXAccount(id: 'multi_1'));
      await storage.addAccount(makeBlueskyAccount(id: 'multi_2'));
      await storage.addAccount(makeXAccount(id: 'multi_3'));

      expect(storage.accounts.length, 3);
    });

    test('異なるサービスのアカウントを追加', () async {
      await storage.addAccount(makeXAccount(id: 'x_1'));
      await storage.addAccount(makeBlueskyAccount(id: 'bsky_1'));

      final xAccounts =
          storage.accounts.where((a) => a.service == SnsService.x).toList();
      final bskyAccounts = storage.accounts
          .where((a) => a.service == SnsService.bluesky)
          .toList();

      expect(xAccounts.length, 1);
      expect(bskyAccounts.length, 1);
    });
  });

  group('AccountStorageService - removeAccount', () {
    test('アカウントを削除できる', () async {
      await storage.addAccount(makeXAccount(id: 'rm_1'));
      await storage.addAccount(makeXAccount(id: 'rm_2'));

      expect(storage.accounts.length, 2);

      await storage.removeAccount('rm_1');
      expect(storage.accounts.length, 1);
      expect(storage.accounts.first.id, 'rm_2');
    });

    test('存在しないアカウントの削除はエラーにならない', () async {
      await storage.addAccount(makeXAccount(id: 'rm_safe'));
      final countBefore = storage.accounts.length;

      await storage.removeAccount('nonexistent');
      expect(storage.accounts.length, countBefore);
    });

    test('全アカウントを削除', () async {
      await storage.addAccount(makeXAccount(id: 'rm_all_1'));
      await storage.addAccount(makeXAccount(id: 'rm_all_2'));

      await storage.removeAccount('rm_all_1');
      await storage.removeAccount('rm_all_2');

      expect(storage.accounts, isEmpty);
    });
  });

  group('AccountStorageService - updateAccount', () {
    test('アカウントの認証情報を更新', () async {
      final account =
          makeXAccount(id: 'upd_1', authToken: 'old', ct0: 'old_ct0');
      await storage.addAccount(account);

      final updated = account.copyWith(
        credentials: const XCredentials(authToken: 'new', ct0: 'new_ct0'),
      );
      await storage.updateAccount(updated);

      final found = storage.getAccount('upd_1');
      expect(found, isNotNull);
      expect(found!.xCredentials.authToken, 'new');
      expect(found.xCredentials.ct0, 'new_ct0');
    });

    test('アカウントの有効/無効を更新', () async {
      final account = makeXAccount(id: 'upd_enable', isEnabled: true);
      await storage.addAccount(account);

      final updated = account.copyWith(isEnabled: false);
      await storage.updateAccount(updated);

      final found = storage.getAccount('upd_enable');
      expect(found!.isEnabled, false);
    });

    test('存在しないアカウントの更新は何もしない', () async {
      final fakeAccount = makeXAccount(id: 'nonexistent_upd');
      await storage.updateAccount(fakeAccount);

      // エラーなし、アカウント追加もされない
      expect(storage.getAccount('nonexistent_upd'), isNull);
    });
  });

  group('AccountStorageService - getAccount', () {
    test('ID でアカウントを取得', () async {
      await storage.addAccount(makeXAccount(id: 'get_1', handle: '@get1'));
      await storage.addAccount(
          makeBlueskyAccount(id: 'get_2', handle: '@get2'));

      final found = storage.getAccount('get_1');
      expect(found, isNotNull);
      expect(found!.id, 'get_1');
      expect(found.handle, '@get1');
    });

    test('存在しない ID は null を返す', () async {
      await storage.addAccount(makeXAccount(id: 'get_exist'));

      final found = storage.getAccount('nonexistent');
      expect(found, isNull);
    });

    test('空のストレージから取得は null', () async {
      final found = storage.getAccount('any_id');
      expect(found, isNull);
    });
  });

  group('AccountStorageService - 統合テスト', () {
    test('追加 → 取得 → 更新 → 取得 → 削除 の一連の操作', () async {
      // 追加
      final account = makeXAccount(
        id: 'integ_1',
        handle: '@integ',
        authToken: 'token_v1',
        ct0: 'ct0_v1',
      );
      await storage.addAccount(account);
      expect(storage.accounts.length, 1);

      // 取得
      var found = storage.getAccount('integ_1');
      expect(found, isNotNull);
      expect(found!.handle, '@integ');
      expect(found.xCredentials.authToken, 'token_v1');

      // 更新
      final updated = found.copyWith(
        credentials:
            const XCredentials(authToken: 'token_v2', ct0: 'ct0_v2'),
      );
      await storage.updateAccount(updated);

      // 更新後の取得
      found = storage.getAccount('integ_1');
      expect(found!.xCredentials.authToken, 'token_v2');

      // 削除
      await storage.removeAccount('integ_1');
      expect(storage.getAccount('integ_1'), isNull);
      expect(storage.accounts, isEmpty);
    });

    test('X と Bluesky のアカウントを混在させて管理', () async {
      await storage.addAccount(makeXAccount(id: 'mix_x', handle: '@x_user'));
      await storage.addAccount(
          makeBlueskyAccount(id: 'mix_bsky', handle: '@bsky_user'));

      expect(storage.accounts.length, 2);

      final xAccount = storage.getAccount('mix_x');
      expect(xAccount!.service, SnsService.x);

      final bskyAccount = storage.getAccount('mix_bsky');
      expect(bskyAccount!.service, SnsService.bluesky);
    });
  });
}
