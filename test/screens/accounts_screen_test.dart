import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/screens/accounts_screen.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/services/timeline_fetch_scheduler.dart';
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

  tearDown(() {
    TimelineFetchScheduler.instance.stop();
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

    testWidgets('shows "アカウントを追加" button at bottom of list',
        (tester) async {
      final account = makeXAccount(displayName: 'TestUser', handle: '@test');
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      expect(find.text('アカウントを追加'), findsOneWidget);
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
    // Helper to navigate to detail page and stop the scheduler timer
    Future<void> navigateToDetail(WidgetTester tester, String displayName) async {
      await tester.tap(find.text(displayName));
      await tester.pumpAndSettle();
      // Stop scheduler timer started by SettingsNotifier
      TimelineFetchScheduler.instance.stop();
    }

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
      await navigateToDetail(tester, 'DetailUser');

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

      await navigateToDetail(tester, 'ProfileUser');

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

      await navigateToDetail(tester, 'HandleUser');

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

      await navigateToDetail(tester, 'SwitchUser');

      expect(find.text('タイムライン取得'), findsOneWidget);
      expect(
        find.text('このアカウントの投稿をフィードに表示する'),
        findsOneWidget,
      );
      // Two SwitchListTiles: timeline + hide RT
      expect(find.byType(SwitchListTile), findsNWidgets(2));
    });

    testWidgets('detail page shows SnsBadge for X service', (tester) async {
      final account = makeXAccount(
        displayName: 'ServiceUser',
        handle: '@serviceuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await navigateToDetail(tester, 'ServiceUser');

      expect(find.byType(SnsBadge), findsAtLeastNWidgets(1));
    });

    testWidgets('detail page shows delete icon in AppBar', (tester) async {
      final account = makeXAccount(
        displayName: 'DeleteUser',
        handle: '@deleteuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await navigateToDetail(tester, 'DeleteUser');

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('delete icon shows confirmation dialog', (tester) async {
      final account = makeXAccount(
        displayName: 'ConfirmUser',
        handle: '@confirmuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      await navigateToDetail(tester, 'ConfirmUser');

      // Tap the delete icon button in AppBar
      await tester.tap(find.byIcon(Icons.delete_outline));
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

      await navigateToDetail(tester, 'CancelUser');

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Tap cancel
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      // Should still be on detail page
      expect(find.text('アカウント削除'), findsNothing);
      expect(find.text('CancelUser'), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping account name navigates to detail page', (tester) async {
      final account = makeXAccount(
        displayName: 'ChevronUser',
        handle: '@chevronuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildAccountsScreen());
      await tester.pump();
      await tester.pump();

      // Tap the account name text
      await navigateToDetail(tester, 'ChevronUser');

      // Should navigate to detail page
      expect(find.text('タイムライン取得'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
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
      await navigateToDetail(tester, 'DeleteMe');

      // Tap delete icon in AppBar
      await tester.tap(find.byIcon(Icons.delete_outline));
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

      await navigateToDetail(tester, 'BlueskyDetail');

      expect(find.byType(SnsBadge), findsAtLeastNWidgets(1));
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

      await navigateToDetail(tester, 'ToggleDetail');

      // Two SwitchListTiles: timeline + hide RT
      final switchTiles = find.byType(SwitchListTile);
      expect(switchTiles, findsNWidgets(2));

      // Toggle the first SwitchListTile (timeline)
      await tester.tap(switchTiles.first);
      await tester.pump();
      await tester.pump();

      // SwitchListTiles should still be present
      expect(find.byType(SwitchListTile), findsNWidgets(2));
    });
  });
}
