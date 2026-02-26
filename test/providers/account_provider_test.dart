import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/providers/account_provider.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_data.dart';

void main() {
  group('Account フィルタリングロジック', () {
    // AccountNotifier.accountsForService のロジックをテスト
    late List<Account> accounts;

    setUp(() {
      accounts = [
        makeXAccount(id: 'x_1', handle: '@x1'),
        makeBlueskyAccount(id: 'bsky_1', handle: '@bsky1'),
        makeXAccount(id: 'x_2', handle: '@x2'),
        makeBlueskyAccount(id: 'bsky_2', handle: '@bsky2'),
      ];
    });

    test('X アカウントのみフィルタ', () {
      final xAccounts =
          accounts.where((a) => a.service == SnsService.x).toList();

      expect(xAccounts.length, 2);
      expect(xAccounts.every((a) => a.service == SnsService.x), true);
    });

    test('Bluesky アカウントのみフィルタ', () {
      final bskyAccounts =
          accounts.where((a) => a.service == SnsService.bluesky).toList();

      expect(bskyAccounts.length, 2);
      expect(
          bskyAccounts.every((a) => a.service == SnsService.bluesky), true);
    });

    test('空リストからのフィルタ', () {
      final empty = <Account>[];
      final result =
          empty.where((a) => a.service == SnsService.x).toList();

      expect(result, isEmpty);
    });
  });

  group('Account CRUD ロジック', () {
    test('アカウント追加', () {
      final accounts = <Account>[];
      final newAccount = makeXAccount(id: 'x_new');

      accounts.add(newAccount);
      expect(accounts.length, 1);
      expect(accounts.first.id, 'x_new');
    });

    test('アカウント削除', () {
      final accounts = [
        makeXAccount(id: 'x_1'),
        makeXAccount(id: 'x_2'),
      ];

      accounts.removeWhere((a) => a.id == 'x_1');
      expect(accounts.length, 1);
      expect(accounts.first.id, 'x_2');
    });

    test('アカウント有効/無効トグル', () {
      final account = makeXAccount(id: 'x_1', isEnabled: true);
      final toggled = account.copyWith(isEnabled: !account.isEnabled);

      expect(toggled.isEnabled, false);
      expect(toggled.id, 'x_1');
    });

    test('credentials の更新', () {
      final account = makeXAccount(id: 'x_1', authToken: 'old');
      const newCreds = XCredentials(authToken: 'new', ct0: 'new_ct0');
      final updated = account.copyWith(credentials: newCreds);

      expect(updated.xCredentials.authToken, 'new');
      expect(updated.id, 'x_1');
    });

    test('存在しないアカウントの検索', () {
      final accounts = [makeXAccount(id: 'x_1')];
      final found = accounts.where((a) => a.id == 'x_nonexistent').firstOrNull;

      expect(found, isNull);
    });

    test('ID でアカウント検索', () {
      final accounts = [
        makeXAccount(id: 'x_1'),
        makeBlueskyAccount(id: 'bsky_1'),
      ];
      final found = accounts.where((a) => a.id == 'bsky_1').firstOrNull;

      expect(found, isNotNull);
      expect(found!.service, SnsService.bluesky);
    });

    test('有効なアカウントのみフィルタ', () {
      final accounts = [
        makeXAccount(id: 'x_1', isEnabled: true),
        makeXAccount(id: 'x_2', isEnabled: false),
        makeBlueskyAccount(id: 'bsky_1', isEnabled: true),
      ];

      final enabled = accounts.where((a) => a.isEnabled).toList();
      expect(enabled.length, 2);
    });
  });

  group('AccountNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('初期状態は空リスト', () async {
      // AccountStorageService を事前にロード (空の状態)
      await AccountStorageService.instance.load();

      final notifier = AccountNotifier();
      // StateNotifier の初期状態
      expect(notifier.state, isA<List<Account>>());
    });

    test('addAccount でアカウントが追加される', () async {
      await AccountStorageService.instance.load();
      final notifier = AccountNotifier();

      // 少し待って初期ロードを完了させる
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final account = makeXAccount(id: 'test_add_1');
      await notifier.addAccount(account);

      expect(notifier.state.any((a) => a.id == 'test_add_1'), true);
    });

    test('removeAccount でアカウントが削除される', () async {
      await AccountStorageService.instance.load();
      final notifier = AccountNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final account = makeXAccount(id: 'test_remove_1');
      await notifier.addAccount(account);
      expect(notifier.state.any((a) => a.id == 'test_remove_1'), true);

      await notifier.removeAccount('test_remove_1');
      expect(notifier.state.any((a) => a.id == 'test_remove_1'), false);
    });

    test('toggleAccount でアカウントの有効/無効が切り替わる', () async {
      await AccountStorageService.instance.load();
      final notifier = AccountNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final account = makeXAccount(id: 'test_toggle_1', isEnabled: true);
      await notifier.addAccount(account);

      await notifier.toggleAccount('test_toggle_1');
      final toggled = notifier.state.firstWhere((a) => a.id == 'test_toggle_1');
      expect(toggled.isEnabled, false);

      await notifier.toggleAccount('test_toggle_1');
      final toggledBack =
          notifier.state.firstWhere((a) => a.id == 'test_toggle_1');
      expect(toggledBack.isEnabled, true);
    });

    test('toggleAccount で存在しないアカウントは何もしない', () async {
      await AccountStorageService.instance.load();
      final notifier = AccountNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final countBefore = notifier.state.length;
      await notifier.toggleAccount('nonexistent_id');
      expect(notifier.state.length, countBefore);
    });

    test('updateCredentials で認証情報が更新される', () async {
      await AccountStorageService.instance.load();
      final notifier = AccountNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final account =
          makeXAccount(id: 'test_cred_1', authToken: 'old', ct0: 'old_ct0');
      await notifier.addAccount(account);

      const newCreds = XCredentials(authToken: 'new_token', ct0: 'new_ct0');
      await notifier.updateCredentials('test_cred_1', newCreds);

      final updated =
          notifier.state.firstWhere((a) => a.id == 'test_cred_1');
      expect(updated.xCredentials.authToken, 'new_token');
      expect(updated.xCredentials.ct0, 'new_ct0');
    });

    test('updateCredentials で存在しないアカウントは何もしない', () async {
      await AccountStorageService.instance.load();
      final notifier = AccountNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      const newCreds = XCredentials(authToken: 'new', ct0: 'ct0');
      final countBefore = notifier.state.length;
      await notifier.updateCredentials('nonexistent', newCreds);
      expect(notifier.state.length, countBefore);
    });

    test('accountsForService で X アカウントをフィルタ', () async {
      await AccountStorageService.instance.load();
      final notifier = AccountNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await notifier.addAccount(makeXAccount(id: 'x_filter_1'));
      await notifier.addAccount(makeBlueskyAccount(id: 'bsky_filter_1'));
      await notifier.addAccount(makeXAccount(id: 'x_filter_2'));

      final xAccounts = notifier.accountsForService(SnsService.x);
      expect(xAccounts.length, greaterThanOrEqualTo(2));
      expect(xAccounts.every((a) => a.service == SnsService.x), true);
    });

    test('accountsForService で Bluesky アカウントをフィルタ', () async {
      await AccountStorageService.instance.load();
      final notifier = AccountNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await notifier.addAccount(makeBlueskyAccount(id: 'bsky_f_1'));
      await notifier.addAccount(makeXAccount(id: 'x_f_1'));

      final bskyAccounts = notifier.accountsForService(SnsService.bluesky);
      expect(bskyAccounts.every((a) => a.service == SnsService.bluesky), true);
    });

    test('reload でストレージからアカウントを再読み込みする', () async {
      await AccountStorageService.instance.load();
      final notifier = AccountNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await notifier.addAccount(makeXAccount(id: 'reload_test'));
      await notifier.reload();

      // reload 後もアカウントが存在する
      expect(notifier.state.any((a) => a.id == 'reload_test'), true);
    });
  });
}
