import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/providers/settings_provider.dart';
import 'package:mobile_omniverse/screens/settings_screen.dart';
import 'package:mobile_omniverse/screens/settings/appearance_settings_screen.dart';
import 'package:mobile_omniverse/screens/settings/button_layout_settings_screen.dart';
import 'package:mobile_omniverse/screens/settings/debug_settings_screen.dart';
import 'package:mobile_omniverse/screens/settings/general_settings_screen.dart';
import 'package:mobile_omniverse/screens/settings/post_display_settings_screen.dart';
import 'package:mobile_omniverse/screens/settings/settings_common.dart';
import 'package:mobile_omniverse/screens/settings/timeline_settings_screen.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/services/timeline_fetch_scheduler.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings_interval': 60,
      // 取得OFFの状態で読み込ませてスケジューラの自動起動を防ぐ。
      // コンストラクタで stopFetching() を呼ぶ方式だと、その保存処理が
      // _loadFromPrefs() と競合して保存値を既定値で上書きしてしまう。
      'settings_fetching_active': false,
    });
    AccountStorageService.instance.setAccountsForTest([]);
  });

  tearDown(() {
    TimelineFetchScheduler.instance.stop();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // PackageInfo のプラットフォームチャネルに依存させない
          packageVersionProvider.overrideWith((ref) async => '1.0.0'),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('設定トップ（ハブ）', () {
    testWidgets('タイトルと各カテゴリの行を表示する', (tester) async {
      await pumpScreen(tester, const SettingsScreen());

      expect(find.text('設定'), findsOneWidget);
      for (final title in [
        '外観',
        '投稿の表示',
        'タイムライン',
        'ボタン配置',
        '一般',
        'アプリ情報',
      ]) {
        expect(find.text(title), findsOneWidget, reason: '「$title」の行が無い');
      }
    });

    testWidgets('操作系ウィジェットはトップに置かない', (tester) async {
      await pumpScreen(tester, const SettingsScreen());

      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(DropdownButton<ThemeMode>), findsNothing);
      expect(find.byType(SegmentedButton<PostCardStyle>), findsNothing);
    });

    testWidgets('各行の subtitle に現在値を表示する', (tester) async {
      await pumpScreen(tester, const SettingsScreen());

      // テーマ・フォントの現在値（どちらもデフォルト）
      expect(find.text('システム・デフォルト'), findsOneWidget);
      // 取得間隔は SharedPreferences の 60 秒が読み込まれる
      expect(find.textContaining('60秒'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
    });

    testWidgets('デバッグ行は解錠前には出ない', (tester) async {
      await pumpScreen(tester, const SettingsScreen());

      expect(find.text('デバッグ'), findsNothing);
    });
  });

  group('設定トップ - 各詳細画面への遷移', () {
    final routes = <String, Type>{
      '外観': AppearanceSettingsScreen,
      '投稿の表示': PostDisplaySettingsScreen,
      'タイムライン': TimelineSettingsScreen,
      'ボタン配置': ButtonLayoutSettingsScreen,
      '一般': GeneralSettingsScreen,
    };

    routes.forEach((title, screenType) {
      testWidgets('「$title」をタップすると $screenType へ遷移する', (tester) async {
        await pumpScreen(tester, const SettingsScreen());

        await tester.tap(find.text(title));
        await tester.pumpAndSettle();

        expect(find.byType(screenType), findsOneWidget);
      });
    });
  });

  group('デバッグの解錠', () {
    /// バージョン5回タップはアプリ情報画面で行い、デバッグ行は設定トップに出る。
    /// 解錠状態が画面をまたいで共有されていることを検証する。
    testWidgets('アプリ情報でバージョンを5回タップすると設定トップにデバッグ行が出る',
        (tester) async {
      await pumpScreen(tester, const SettingsScreen());

      await tester.tap(find.text('アプリ情報'));
      await tester.pumpAndSettle();
      expect(find.text('バージョン'), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('バージョン'));
        await tester.pump();
      }
      // 解錠を知らせる SnackBar のタイマーを消化してから戻る
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('デバッグ'), findsOneWidget);
    });

    testWidgets('4回のタップでは解錠されない', (tester) async {
      await pumpScreen(tester, const SettingsScreen());

      await tester.tap(find.text('アプリ情報'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('バージョン'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('デバッグ'), findsNothing);
    });
  });

  group('外観設定画面', () {
    testWidgets('テーマ・フォント・フォントサイズを表示する', (tester) async {
      await pumpScreen(tester, const AppearanceSettingsScreen());

      expect(find.text('テーマ'), findsOneWidget);
      expect(find.text('フォント'), findsOneWidget);
      expect(find.textContaining('フォントサイズ'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.textContaining('100%'), findsOneWidget);
    });

    testWidgets('テーマの初期値はシステム', (tester) async {
      await pumpScreen(tester, const AppearanceSettingsScreen());

      expect(find.text('システム'), findsAtLeastNWidgets(1));
    });

    testWidgets('テーマのドロップダウンを変更すると反映される', (tester) async {
      await pumpScreen(tester, const AppearanceSettingsScreen());

      final dropdown = find.byType(DropdownButton<ThemeMode>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.text('ダーク').last);
      await tester.pumpAndSettle();

      expect(find.text('ダーク'), findsAtLeastNWidgets(1));
    });

    testWidgets('フォントサイズのスライダーを動かすと表示が変わる', (tester) async {
      await pumpScreen(tester, const AppearanceSettingsScreen());

      expect(find.textContaining('100%'), findsOneWidget);

      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('100%'), findsNothing);
    });
  });

  group('投稿の表示設定画面', () {
    testWidgets('プレビューと各項目を表示する', (tester) async {
      await pumpScreen(tester, const PostDisplaySettingsScreen());

      expect(find.text('プレビュー'), findsOneWidget);
      expect(find.text('投稿スタイル'), findsOneWidget);
      expect(find.text('プレビューサイズ'), findsOneWidget);
      expect(find.text('匿名モード'), findsOneWidget);
      expect(find.text('センシティブ'), findsOneWidget);
    });

    testWidgets('ボタン位置はこの画面に含まれない', (tester) async {
      await pumpScreen(tester, const PostDisplaySettingsScreen());

      expect(find.text('ボタン位置'), findsNothing);
    });
  });

  group('タイムライン設定画面', () {
    testWidgets('取得間隔・ドリップ速度・RT非表示を表示する', (tester) async {
      await pumpScreen(tester, const TimelineSettingsScreen());

      expect(find.text('取得間隔'), findsOneWidget);
      expect(find.text('ドリップ速度'), findsOneWidget);
      expect(find.text('RT / リポストを非表示'), findsOneWidget);
    });

    testWidgets('取得間隔は保存値を選択している', (tester) async {
      await pumpScreen(tester, const TimelineSettingsScreen());

      expect(find.text('60秒'), findsOneWidget);
    });
  });

  group('ボタン配置設定画面', () {
    testWidgets('ヘッダーバーの各スイッチとボタン位置を表示する', (tester) async {
      await pumpScreen(tester, const ButtonLayoutSettingsScreen());

      expect(find.text('フェッチタイマー'), findsOneWidget);
      expect(find.text('匿名切替'), findsOneWidget);
      expect(find.text('スリープ防止'), findsOneWidget);
      expect(find.text('センシティブ切替'), findsOneWidget);
      expect(find.text('RT非表示切替'), findsOneWidget);
      // 投稿の表示から移設した項目
      expect(find.text('ボタン位置'), findsOneWidget);
    });
  });

  group('一般設定画面', () {
    testWidgets('スリープ防止・保存先・リセットを表示する', (tester) async {
      await pumpScreen(tester, const GeneralSettingsScreen());

      expect(find.text('画面スリープ防止'), findsOneWidget);
      expect(find.text('画像の保存先'), findsOneWidget);
      expect(find.text('設定をデフォルトに戻す'), findsOneWidget);
    });
  });

  group('デバッグ設定画面', () {
    testWidgets('各デバッグ項目を表示する', (tester) async {
      await pumpScreen(tester, const DebugSettingsScreen());

      expect(find.text('アクションログ'), findsOneWidget);
      expect(find.text('queryId 管理'), findsOneWidget);
      expect(find.text('features 管理'), findsOneWidget);
      expect(find.text('タイムライン取得'), findsOneWidget);
    });

    testWidgets('キャッシュクリアと解錠解除の項目まで辿れる', (tester) async {
      await pumpScreen(tester, const DebugSettingsScreen());

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('デバッグメニューを隠す'), 200.0,
          scrollable: scrollable);

      expect(find.text('キャッシュをクリア'), findsOneWidget);
      expect(find.text('デバッグメニューを隠す'), findsOneWidget);
    });
  });
}
