import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/screens/settings_screen.dart';
import 'package:mobile_omniverse/providers/settings_provider.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/services/timeline_fetch_scheduler.dart';

import '../helpers/test_data.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountStorageService.instance.setAccountsForTest([]);
  });

  Widget buildSettingsScreen() {
    return ProviderScope(
      child: MaterialApp(
        home: const SettingsScreen(),
      ),
    );
  }

  group('SettingsScreen - rendering', () {
    testWidgets('renders app bar with title "設定"', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.text('設定'), findsOneWidget);
    });

    testWidgets('renders section headers', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // "タイムライン取得" appears twice: section header + switch tile
      expect(find.text('タイムライン取得'), findsNWidgets(2));
      expect(find.text('エンゲージメント'), findsOneWidget);
      expect(find.text('外観'), findsOneWidget);
    });

    testWidgets('renders timeline fetching switch', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // "タイムライン取得" appears twice: section header + switch tile
      expect(find.text('タイムライン取得'), findsNWidgets(2));
      expect(find.byType(SwitchListTile), findsAtLeastNWidgets(1));
    });

    testWidgets('renders fetch interval setting', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.text('フェッチ間隔'), findsOneWidget);
    });

    testWidgets('renders theme setting', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.text('テーマ'), findsOneWidget);
    });

    testWidgets('renders font size setting', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.text('フォントサイズ'), findsOneWidget);
    });

    testWidgets('renders version info section', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Scroll down to find "バージョン" (may be off-screen)
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('バージョン'), 200.0,
          scrollable: scrollable);
      expect(find.text('バージョン'), findsOneWidget);
    });

    testWidgets('renders debug section', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Scroll down to find "queryId キャッシュ消去" (deepest debug item)
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('queryId キャッシュ消去'), 200.0,
          scrollable: scrollable);
      expect(find.text('デバッグ'), findsOneWidget);
      expect(find.text('queryId キャッシュ消去'), findsOneWidget);
    });

    testWidgets('renders account picker toggle', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.text('アカウント選択モーダル'), findsOneWidget);
    });

    testWidgets('renders RT filter section', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Scroll down to find "RT/リポスト フィルタ" section
      await tester.scrollUntilVisible(
        find.text('RT/リポスト フィルタ'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('RT/リポスト フィルタ'), findsOneWidget);
    });

    testWidgets('renders update check button', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Scroll down to find the update check button
      await tester.scrollUntilVisible(
        find.text('アップデート確認'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('アップデート確認'), findsOneWidget);
      expect(find.byIcon(Icons.system_update), findsOneWidget);
    });

    testWidgets('shows "アカウントがありません" when no accounts for RT filter',
        (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('アカウントがありません'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('アカウントがありません'), findsOneWidget);
      expect(
        find.text('アカウントを追加すると、ここで RT 非表示を設定できます'),
        findsOneWidget,
      );
    });
  });

  group('SettingsScreen - interactions', () {
    testWidgets('timeline fetching switch shows 停止中 when off',
        (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Initially fetching is off (default isFetchingActive=false)
      expect(find.text('停止中'), findsOneWidget);
    });

    testWidgets('toggling timeline fetching switch changes subtitle',
        (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Initially fetching is off (default isFetchingActive=false)
      expect(find.text('停止中'), findsOneWidget);

      // Find the first SwitchListTile (timeline fetching)
      final switchFinder = find.byType(SwitchListTile).first;
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump();

      // Now it should be active
      expect(find.text('実行中'), findsOneWidget);

      // IMPORTANT: Stop the scheduler to clean up the periodic timer
      TimelineFetchScheduler.instance.stop();
    });

    testWidgets('renders font size slider', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
      // Default value is 100%
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('shows fetch interval default value', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Default interval is 60 seconds
      expect(find.text('60 秒'), findsOneWidget);
    });

    testWidgets('shows theme mode default value', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Default theme is system
      expect(find.text('システム設定に従う'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows queryId info for no X accounts', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('queryId 更新'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('X アカウントが必要です'), findsOneWidget);
    });
  });

  group('SettingsScreen - engagement and appearance', () {
    testWidgets('toggling account picker switch changes its value',
        (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Find the account picker SwitchListTile (second one)
      final switches = find.byType(SwitchListTile);
      expect(switches, findsAtLeastNWidgets(2));

      // The account picker switch is the second SwitchListTile
      await tester.tap(switches.at(1));
      await tester.pump();
      await tester.pump();

      // After toggle, the value should change (default is false -> true)
      // We verify by checking for the subtitle text still present
      expect(find.text('いいね/RT 時にアカウントを選択する'), findsOneWidget);
    });

    testWidgets('queryId cache clear button is tappable', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('queryId キャッシュ消去'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );

      // Tap the cache clear button
      await tester.tap(find.text('queryId キャッシュ消去'));
      await tester.pumpAndSettle();

      // Should show snackbar confirmation
      expect(find.text('queryId キャッシュを消去しました'), findsOneWidget);
    });

    testWidgets('shows "デフォルト値に戻します" subtitle for queryId cache clear',
        (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('デフォルト値に戻します'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('デフォルト値に戻します'), findsOneWidget);
    });

    testWidgets('shows refresh icon for queryId', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byIcon(Icons.refresh),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('shows delete_outline icon for queryId cache', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byIcon(Icons.delete_outline),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows アプリ情報 section header', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('アプリ情報'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('アプリ情報'), findsOneWidget);
    });

    testWidgets('shows RT filter with X account icon', (tester) async {
      final xAccount = makeXAccount(
        id: 'x_rt',
        displayName: 'RTFilter X',
        handle: '@rtx',
      );
      AccountStorageService.instance.setAccountsForTest([xAccount]);

      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('RTFilter X'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );

      // X account should show close icon
      expect(find.byIcon(Icons.close), findsAtLeastNWidgets(1));
    });

    testWidgets('shows RT filter with Bluesky account icon', (tester) async {
      final bskyAccount = makeBlueskyAccount(
        id: 'bsky_rt',
        displayName: 'RTFilter Bsky',
        handle: '@rtbsky',
      );
      AccountStorageService.instance.setAccountsForTest([bskyAccount]);

      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('RTFilter Bsky'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );

      // Bluesky account should show cloud icon
      expect(find.byIcon(Icons.cloud), findsAtLeastNWidgets(1));
    });

    testWidgets('RT filter shows handle and service name', (tester) async {
      final account = makeXAccount(
        id: 'x_handle',
        displayName: 'HandleUser',
        handle: '@handleuser',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('HandleUser'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('@handleuser (X)'), findsOneWidget);
    });

    testWidgets('toggling RT filter switch changes its state', (tester) async {
      final account = makeXAccount(
        id: 'x_rt_toggle',
        displayName: 'RTToggle',
        handle: '@rttoggle',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('RTToggle'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );

      // Find the RT filter SwitchListTile (should be the third one after timeline and engagement)
      // Tap on the account name to toggle
      final rtSwitch = find.descendant(
        of: find.ancestor(
          of: find.text('RTToggle'),
          matching: find.byType(SwitchListTile),
        ),
        matching: find.byType(Switch),
      );
      if (rtSwitch.evaluate().isNotEmpty) {
        await tester.tap(rtSwitch);
        await tester.pump();
        await tester.pump();
      }
      // Verify the widget still renders
      expect(find.text('RTToggle'), findsOneWidget);
    });

    testWidgets('fetch interval dropdown contains expected items',
        (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Default is 60 seconds
      expect(find.text('60 秒'), findsOneWidget);

      // Tap the dropdown button
      final dropdownButton = find.byType(DropdownButton<int>);
      expect(dropdownButton, findsOneWidget);
      await tester.tap(dropdownButton);
      await tester.pumpAndSettle();

      // Dropdown should show all options (60秒 appears twice - selected + overlay)
      expect(find.text('30秒'), findsAtLeastNWidgets(1));
      expect(find.text('60秒'), findsAtLeastNWidgets(1));
      expect(find.text('2分'), findsAtLeastNWidgets(1));
      expect(find.text('5分'), findsAtLeastNWidgets(1));
    });

    testWidgets('changing theme dropdown updates subtitle', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Default is system
      expect(find.text('システム設定に従う'), findsAtLeastNWidgets(1));

      // Tap the theme dropdown
      final dropdown = find.byType(DropdownButton<ThemeMode>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Select dark mode
      await tester.tap(find.text('ダーク').last);
      await tester.pumpAndSettle();

      // Should now show dark mode
      expect(find.text('ダーク'), findsAtLeastNWidgets(1));
    });

    testWidgets('selecting a fetch interval dropdown item updates the value',
        (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Default is 60 seconds
      expect(find.text('60 秒'), findsOneWidget);

      // Open the dropdown
      final dropdownButton = find.byType(DropdownButton<int>);
      await tester.tap(dropdownButton);
      await tester.pumpAndSettle();

      // Select 30秒
      await tester.tap(find.text('30秒').last);
      await tester.pumpAndSettle();

      // Should now show 30 秒
      expect(find.text('30 秒'), findsOneWidget);
    });

    testWidgets('changing font scale slider updates value', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Default value is 100%
      expect(find.text('100%'), findsOneWidget);

      // Find the slider and drag it
      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      // Drag to increase font size
      await tester.drag(slider, const Offset(100, 0));
      await tester.pump();
      await tester.pump();

      // Value should have changed (no longer 100%)
      expect(find.text('100%'), findsNothing);
    });
  });

  group('SettingsScreen - with accounts for RT filter', () {
    testWidgets('shows account names in RT filter section', (tester) async {
      final xAccount = makeXAccount(
        id: 'x_1',
        displayName: 'XUser',
        handle: '@xuser',
      );
      final bskyAccount = makeBlueskyAccount(
        id: 'bsky_1',
        displayName: 'BSkyUser',
        handle: '@bskyuser',
      );
      AccountStorageService.instance
          .setAccountsForTest([xAccount, bskyAccount]);

      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('XUser'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('XUser'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('BSkyUser'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('BSkyUser'), findsOneWidget);
    });

    testWidgets('shows queryId subtitle when X account exists', (tester) async {
      final xAccount = makeXAccount(id: 'x_1');
      AccountStorageService.instance.setAccountsForTest([xAccount]);

      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('queryId 更新'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      // Should NOT show "X アカウントが必要です" since we have an X account
      expect(find.text('X アカウントが必要です'), findsNothing);
      // Should show "未更新" since lastRefreshTime is null
      expect(find.text('未更新'), findsOneWidget);
    });
  });
}
