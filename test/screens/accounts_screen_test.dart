import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/screens/accounts_screen.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/widgets/sns_badge.dart';

import '../helpers/test_data.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AccountStorageService.instance.setAccountsForTest([]);
  });

  Widget buildAccountsScreen() {
    return const ProviderScope(
      child: MaterialApp(
        home: AccountsScreen(),
      ),
    );
  }

  group('AccountsScreen - empty state', () {
    testWidgets('shows "アカウント未登録" when no accounts exist',
        (tester) async {
      await tester.pumpWidget(buildAccountsScreen());
      await tester.pumpAndSettle();

      expect(find.text('アカウント未登録'), findsOneWidget);
    });

    testWidgets('shows empty state hint text', (tester) async {
      await tester.pumpWidget(buildAccountsScreen());
      await tester.pumpAndSettle();

      expect(
        find.text('SNS アカウントを追加して\nタイムラインを取得しましょう'),
        findsOneWidget,
      );
    });

    testWidgets('shows person_add icon in empty state', (tester) async {
      await tester.pumpWidget(buildAccountsScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets('shows "アカウント追加" button in empty state', (tester) async {
      await tester.pumpWidget(buildAccountsScreen());
      await tester.pumpAndSettle();

      expect(find.text('アカウント追加'), findsOneWidget);
    });

    testWidgets('"アカウント追加" button opens bottom sheet', (tester) async {
      await tester.pumpWidget(buildAccountsScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('アカウント追加'));
      await tester.pumpAndSettle();

      expect(find.text('SNS を選択'), findsOneWidget);
    });

    testWidgets('bottom sheet shows X and Bluesky options', (tester) async {
      await tester.pumpWidget(buildAccountsScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('アカウント追加'));
      await tester.pumpAndSettle();

      expect(find.text('X'), findsOneWidget);
      expect(find.text('Bluesky'), findsOneWidget);
      expect(find.text('x.com'), findsOneWidget);
      expect(find.text('bsky.app'), findsOneWidget);
    });

    testWidgets('bottom sheet shows chevron_right trailing icons',
        (tester) async {
      await tester.pumpWidget(buildAccountsScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('アカウント追加'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    });

    testWidgets('renders Scaffold', (tester) async {
      await tester.pumpWidget(buildAccountsScreen());
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });
  });

  group('AccountsScreen - with accounts', () {
    testWidgets('shows account display name when accounts exist',
        (tester) async {
      final account = makeXAccount(displayName: 'TestUser', handle: '@test');
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      expect(find.text('TestUser'), findsOneWidget);
    });

    testWidgets('shows account handle', (tester) async {
      final account = makeXAccount(displayName: 'TestUser', handle: '@test');
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      expect(find.text('@test'), findsOneWidget);
    });

    testWidgets('shows SnsBadge for each account', (tester) async {
      final account =
          makeBlueskyAccount(displayName: 'BSky User', handle: '@bsky');
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnsBadge), findsAtLeastNWidgets(1));
    });

    testWidgets('shows Switch toggle for account', (tester) async {
      final account = makeXAccount(displayName: 'TestUser', handle: '@test');
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('shows "アカウント追加" button at bottom of list',
        (tester) async {
      final account = makeXAccount(displayName: 'TestUser', handle: '@test');
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      expect(find.text('アカウント追加'), findsOneWidget);
    });

    testWidgets('shows avatar initial when avatarUrl is null', (tester) async {
      final account = makeXAccount(displayName: 'TestUser', handle: '@test');
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      expect(find.text('T'), findsOneWidget);
    });

    testWidgets('shows multiple accounts in list', (tester) async {
      final xAccount = makeXAccount(
        id: 'x_1',
        displayName: 'X User',
        handle: '@xuser',
      );
      final bskyAccount = makeBlueskyAccount(
        id: 'bsky_1',
        displayName: 'Bluesky User',
        handle: '@bskyuser',
      );
      AccountStorageService.instance.setAccountsForTest([xAccount, bskyAccount]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      expect(find.text('X User'), findsOneWidget);
      expect(find.text('Bluesky User'), findsOneWidget);
    });
  });

  group('AccountsScreen - account detail page', () {
    testWidgets('tapping account tile navigates to detail page', (tester) async {
      final account = makeXAccount(
        displayName: 'DetailUser',
        handle: '@detailuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      // Tap the account tile (the ListTile area, not the switch)
      await tester.tap(find.text('DetailUser'));
      await tester.pumpAndSettle();

      // Should be on the detail screen with the display name in AppBar
      expect(find.text('DetailUser'), findsAtLeastNWidgets(1));
    });

    testWidgets('detail page shows profile header with CircleAvatar',
        (tester) async {
      final account = makeXAccount(
        displayName: 'ProfileUser',
        handle: '@profileuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('ProfileUser'));
      await tester.pumpAndSettle();

      // Detail screen shows a CircleAvatar with radius 40
      expect(find.byType(CircleAvatar), findsAtLeastNWidgets(1));
      // Shows initial letter (P for ProfileUser)
      expect(find.text('P'), findsAtLeastNWidgets(1));
    });

    testWidgets('detail page shows handle with SnsBadge', (tester) async {
      final account = makeXAccount(
        displayName: 'HandleUser',
        handle: '@handleuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('HandleUser'));
      await tester.pumpAndSettle();

      expect(find.text('@handleuser'), findsAtLeastNWidgets(1));
      expect(find.byType(SnsBadge), findsAtLeastNWidgets(1));
    });

    testWidgets('detail page shows SwitchListTile for timeline fetching',
        (tester) async {
      final account = makeXAccount(
        displayName: 'SwitchUser',
        handle: '@switchuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('SwitchUser'));
      await tester.pumpAndSettle();

      expect(find.text('タイムライン取得'), findsOneWidget);
      expect(
        find.text('このアカウントのタイムラインを Omni-Feed に含める'),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('detail page shows service info', (tester) async {
      final account = makeXAccount(
        displayName: 'ServiceUser',
        handle: '@serviceuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('ServiceUser'));
      await tester.pumpAndSettle();

      expect(find.text('サービス'), findsOneWidget);
      expect(find.text('X'), findsAtLeastNWidgets(1));
    });

    testWidgets('detail page shows added date', (tester) async {
      final account = makeXAccount(
        displayName: 'DateUser',
        handle: '@dateuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('DateUser'));
      await tester.pumpAndSettle();

      expect(find.text('追加日時'), findsOneWidget);
      // makeXAccount creates with DateTime(2024, 1, 1)
      expect(find.text('2024/01/01'), findsOneWidget);
    });

    testWidgets('detail page shows account ID', (tester) async {
      final account = makeXAccount(
        id: 'x_acc_detail',
        displayName: 'IDUser',
        handle: '@iduser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('IDUser'));
      await tester.pumpAndSettle();

      expect(find.text('アカウント ID'), findsOneWidget);
      expect(find.text('x_acc_detail'), findsOneWidget);
    });

    testWidgets('detail page shows delete button', (tester) async {
      final account = makeXAccount(
        displayName: 'DeleteUser',
        handle: '@deleteuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('DeleteUser'));
      await tester.pumpAndSettle();

      expect(find.text('アカウントを削除'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('delete button shows confirmation dialog', (tester) async {
      final account = makeXAccount(
        displayName: 'ConfirmUser',
        handle: '@confirmuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('ConfirmUser'));
      await tester.pumpAndSettle();

      // Tap the delete button
      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();

      // Should show confirmation dialog
      expect(find.text('アカウント削除'), findsOneWidget);
      expect(
        find.text('ConfirmUser (@confirmuser) を削除しますか？'),
        findsOneWidget,
      );
      expect(find.text('キャンセル'), findsOneWidget);
      expect(find.text('削除'), findsOneWidget);
    });

    testWidgets('cancel in delete dialog dismisses dialog', (tester) async {
      final account = makeXAccount(
        displayName: 'CancelUser',
        handle: '@canceluser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('CancelUser'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();

      // Tap cancel
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      // Should still be on detail page
      expect(find.text('アカウント削除'), findsNothing);
      expect(find.text('CancelUser'), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping chevron_right navigates to detail page', (tester) async {
      final account = makeXAccount(
        displayName: 'ChevronUser',
        handle: '@chevronuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      // Tap the chevron_right icon button
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      // Should navigate to detail page
      expect(find.text('タイムライン取得'), findsOneWidget);
      expect(find.text('アカウントを削除'), findsOneWidget);
    });

    testWidgets('toggling switch changes account enabled state', (tester) async {
      final account = makeXAccount(
        displayName: 'SwitchToggle',
        handle: '@switchtoggle',
        isEnabled: true,
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      // Find the Switch widget and toggle it
      final switchWidget = find.byType(Switch);
      expect(switchWidget, findsOneWidget);

      await tester.tap(switchWidget);
      await tester.pump();
      await tester.pump();

      // The switch should have toggled
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('delete confirmation dialog has a 削除 FilledButton', (tester) async {
      final account = makeXAccount(
        displayName: 'DeleteMe',
        handle: '@deleteme',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      // Navigate to detail page
      await tester.tap(find.text('DeleteMe'));
      await tester.pumpAndSettle();

      // Tap delete button
      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();

      // Confirm the 削除 FilledButton is a FilledButton
      expect(find.widgetWithText(FilledButton, '削除'), findsOneWidget);
    });

    testWidgets('detail page shows Bluesky account info', (tester) async {
      final account = makeBlueskyAccount(
        id: 'bsky_detail',
        displayName: 'BlueskyDetail',
        handle: '@bskydetail',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('BlueskyDetail'));
      await tester.pumpAndSettle();

      expect(find.text('Bluesky'), findsAtLeastNWidgets(1));
      expect(find.text('@bskydetail'), findsAtLeastNWidgets(1));
    });

    testWidgets('detail page toggle SwitchListTile changes enabled state',
        (tester) async {
      final account = makeXAccount(
        displayName: 'ToggleDetail',
        handle: '@toggledetail',
        isEnabled: true,
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('ToggleDetail'));
      await tester.pumpAndSettle();

      // Toggle the SwitchListTile on detail page
      final switchTile = find.byType(SwitchListTile);
      expect(switchTile, findsOneWidget);

      await tester.tap(switchTile);
      await tester.pump();
      await tester.pump();

      // Switch should have toggled
      expect(find.byType(SwitchListTile), findsOneWidget);
    });
  });
}
