import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/screens/settings_screen.dart';
import 'package:mobile_omniverse/providers/settings_provider.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/services/timeline_fetch_scheduler.dart';

/// SettingsNotifier that does not auto-start the scheduler
class _TestSettingsNotifier extends SettingsNotifier {
  _TestSettingsNotifier() : super() {
    // 自動起動を無効化
    stopFetching();
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings_interval': 60,
    });
    AccountStorageService.instance.setAccountsForTest([]);
  });

  tearDown(() {
    TimelineFetchScheduler.instance.stop();
  });

  Future<void> pumpSettingsScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => _TestSettingsNotifier()),
        ],
        child: MaterialApp(
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// デバッグセクションは「バージョン」を5回タップする隠し機能で解除される。
  /// 解除しないとデバッグ系の項目はウィジェットツリーに存在しない。
  Future<void> unlockDebugSection(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('バージョン'), 200.0,
        scrollable: scrollable);
    await tester.ensureVisible(find.text('バージョン'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('バージョン'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  group('SettingsScreen - rendering', () {
    testWidgets('renders app bar with title "設定"', (tester) async {
      await pumpSettingsScreen(tester);

      expect(find.text('設定'), findsOneWidget);
    });

    testWidgets('renders section headers', (tester) async {
      await pumpSettingsScreen(tester);

      expect(find.text('外観'), findsOneWidget);
      expect(find.text('投稿の表示'), findsOneWidget);
    });

    testWidgets('renders theme setting', (tester) async {
      await pumpSettingsScreen(tester);

      expect(find.text('テーマ'), findsOneWidget);
    });

    testWidgets('renders font size setting', (tester) async {
      await pumpSettingsScreen(tester);

      expect(find.textContaining('フォントサイズ'), findsOneWidget);
    });

    testWidgets('renders 投稿スタイル setting', (tester) async {
      await pumpSettingsScreen(tester);

      expect(find.text('投稿スタイル'), findsOneWidget);
    });

    testWidgets('renders version info section', (tester) async {
      await pumpSettingsScreen(tester);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('バージョン'), 200.0,
          scrollable: scrollable);
      expect(find.text('バージョン'), findsOneWidget);
    });

    testWidgets('renders debug section', (tester) async {
      await pumpSettingsScreen(tester);
      await unlockDebugSection(tester);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('デバッグ'), 200.0,
          scrollable: scrollable);
      expect(find.text('デバッグ'), findsOneWidget);
    });

    testWidgets('renders update check button', (tester) async {
      await pumpSettingsScreen(tester);

      await tester.scrollUntilVisible(
        find.text('アップデート確認'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('アップデート確認'), findsOneWidget);
      expect(find.byIcon(Icons.system_update), findsOneWidget);
    });

    testWidgets('renders アプリ情報 section header', (tester) async {
      await pumpSettingsScreen(tester);

      await tester.scrollUntilVisible(
        find.text('アプリ情報'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('アプリ情報'), findsOneWidget);
    });
  });

  group('SettingsScreen - debug section contents', () {
    Future<void> expandDebugSection(WidgetTester tester) async {
      // デバッグセクションは隠し機能なので、まずバージョン5回タップで解除する
      await unlockDebugSection(tester);
      final scrollable = find.byType(Scrollable).first;
      // Scroll to ensure the debug section is visible and tappable
      await tester.scrollUntilVisible(find.text('デバッグ'), 300.0,
          scrollable: scrollable);
      await tester.pumpAndSettle();
      // Ensure it's centered enough to be tappable
      await tester.ensureVisible(find.text('デバッグ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('デバッグ'));
      await tester.pumpAndSettle();
    }

    testWidgets('debug section contains アクションログ', (tester) async {
      await pumpSettingsScreen(tester);
      await expandDebugSection(tester);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('アクションログ'), 200.0,
          scrollable: scrollable);
      expect(find.text('アクションログ'), findsOneWidget);
    });

    testWidgets('debug section contains queryId 管理', (tester) async {
      await pumpSettingsScreen(tester);
      await expandDebugSection(tester);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('queryId 管理'), 200.0,
          scrollable: scrollable);
      expect(find.text('queryId 管理'), findsOneWidget);
    });

    testWidgets('debug section contains features 管理', (tester) async {
      await pumpSettingsScreen(tester);
      await expandDebugSection(tester);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('features 管理'), 200.0,
          scrollable: scrollable);
      expect(find.text('features 管理'), findsOneWidget);
    });

    testWidgets('debug section contains タイムライン取得 switch', (tester) async {
      await pumpSettingsScreen(tester);
      await expandDebugSection(tester);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('タイムライン取得'), 200.0,
          scrollable: scrollable);
      expect(find.text('タイムライン取得'), findsOneWidget);
    });
  });

  group('SettingsScreen - interactions', () {
    testWidgets('renders font size slider', (tester) async {
      await pumpSettingsScreen(tester);

      expect(find.byType(Slider), findsOneWidget);
      expect(find.textContaining('100%'), findsOneWidget);
    });

    testWidgets('shows fetch interval default value', (tester) async {
      await pumpSettingsScreen(tester);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('取得間隔'), 200.0,
          scrollable: scrollable);

      expect(find.text('取得間隔'), findsOneWidget);
    });

    testWidgets('shows theme mode default value', (tester) async {
      await pumpSettingsScreen(tester);

      expect(find.text('システム'), findsAtLeastNWidgets(1));
    });

    testWidgets('changing theme dropdown updates value', (tester) async {
      await pumpSettingsScreen(tester);

      final dropdown = find.byType(DropdownButton<ThemeMode>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.text('ダーク').last);
      await tester.pumpAndSettle();

      expect(find.text('ダーク'), findsAtLeastNWidgets(1));
    });

    testWidgets('changing font scale slider updates value', (tester) async {
      await pumpSettingsScreen(tester);

      expect(find.textContaining('100%'), findsOneWidget);

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      await tester.drag(slider, const Offset(100, 0));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('100%'), findsNothing);
    });
  });
}
