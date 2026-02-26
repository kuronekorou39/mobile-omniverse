import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsState', () {
    test('初期状態のデフォルト値', () {
      const state = SettingsState();

      expect(state.fetchIntervalSeconds, 60);
      expect(state.isFetchingActive, false);
      expect(state.themeMode, ThemeMode.system);
      expect(state.fontScale, 1.0);
      expect(state.hideRetweetsAccountIds, isEmpty);
      expect(state.showAccountPickerOnEngagement, false);
    });

    test('copyWith で fetchIntervalSeconds を変更', () {
      const state = SettingsState();
      final updated = state.copyWith(fetchIntervalSeconds: 120);

      expect(updated.fetchIntervalSeconds, 120);
      expect(updated.themeMode, ThemeMode.system);
    });

    test('copyWith で themeMode を変更', () {
      const state = SettingsState();
      final updated = state.copyWith(themeMode: ThemeMode.dark);

      expect(updated.themeMode, ThemeMode.dark);
    });

    test('copyWith で fontScale を変更', () {
      const state = SettingsState();
      final updated = state.copyWith(fontScale: 1.5);

      expect(updated.fontScale, 1.5);
    });

    test('copyWith で hideRetweetsAccountIds を変更', () {
      const state = SettingsState();
      final updated = state.copyWith(
        hideRetweetsAccountIds: {'acc_1', 'acc_2'},
      );

      expect(updated.hideRetweetsAccountIds, {'acc_1', 'acc_2'});
    });

    test('copyWith で showAccountPickerOnEngagement を変更', () {
      const state = SettingsState();
      final updated = state.copyWith(showAccountPickerOnEngagement: true);

      expect(updated.showAccountPickerOnEngagement, true);
    });

    test('copyWith で isFetchingActive を変更', () {
      const state = SettingsState();
      final updated = state.copyWith(isFetchingActive: true);

      expect(updated.isFetchingActive, true);
    });

    test('copyWith で変更なし', () {
      const state = SettingsState(
        fetchIntervalSeconds: 90,
        themeMode: ThemeMode.dark,
        fontScale: 1.2,
      );
      final updated = state.copyWith();

      expect(updated.fetchIntervalSeconds, 90);
      expect(updated.themeMode, ThemeMode.dark);
      expect(updated.fontScale, 1.2);
    });

    test('hideRetweetsAccountIds のトグルロジック', () {
      // SettingsNotifier.toggleHideRetweets のロジックを再現
      var current = <String>{};

      // 追加
      current = Set<String>.from(current);
      current.add('acc_1');
      expect(current, {'acc_1'});

      // 再度追加 → 削除
      current = Set<String>.from(current);
      if (current.contains('acc_1')) {
        current.remove('acc_1');
      } else {
        current.add('acc_1');
      }
      expect(current, isEmpty);
    });

    test('isRetweetsHidden のロジック', () {
      const state = SettingsState(
        hideRetweetsAccountIds: {'acc_1', 'acc_3'},
      );

      expect(state.hideRetweetsAccountIds.contains('acc_1'), true);
      expect(state.hideRetweetsAccountIds.contains('acc_2'), false);
      expect(state.hideRetweetsAccountIds.contains('acc_3'), true);
    });

    test('ThemeMode の全パターン', () {
      for (final mode in ThemeMode.values) {
        final state = const SettingsState().copyWith(themeMode: mode);
        expect(state.themeMode, mode);
      }
    });

    test('fontScale の範囲値', () {
      final small = const SettingsState().copyWith(fontScale: 0.8);
      final large = const SettingsState().copyWith(fontScale: 2.0);

      expect(small.fontScale, 0.8);
      expect(large.fontScale, 2.0);
    });
  });

  group('SettingsNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('初期状態はデフォルト値', () {
      final notifier = SettingsNotifier();
      expect(notifier.state.fetchIntervalSeconds, 60);
      expect(notifier.state.isFetchingActive, false);
      expect(notifier.state.themeMode, ThemeMode.system);
      expect(notifier.state.fontScale, 1.0);
      expect(notifier.state.hideRetweetsAccountIds, isEmpty);
      expect(notifier.state.showAccountPickerOnEngagement, false);
    });

    test('setInterval でインターバルが変更される', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.setInterval(120);

      expect(notifier.state.fetchIntervalSeconds, 120);
    });

    test('setInterval で SharedPreferences に保存される', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.setInterval(90);

      // SharedPreferences への保存を確認
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('settings_interval'), 90);
    });

    test('setThemeMode でテーマが変更される', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.setThemeMode(ThemeMode.dark);
      expect(notifier.state.themeMode, ThemeMode.dark);

      notifier.setThemeMode(ThemeMode.light);
      expect(notifier.state.themeMode, ThemeMode.light);

      notifier.setThemeMode(ThemeMode.system);
      expect(notifier.state.themeMode, ThemeMode.system);
    });

    test('setThemeMode で SharedPreferences に保存される', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.setThemeMode(ThemeMode.dark);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('settings_theme_mode'), ThemeMode.dark.index);
    });

    test('setFontScale でフォントスケールが変更される', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.setFontScale(1.5);
      expect(notifier.state.fontScale, 1.5);
    });

    test('setFontScale で SharedPreferences に保存される', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.setFontScale(1.3);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('settings_font_scale'), 1.3);
    });

    test('toggleHideRetweets でアカウントの RT 非表示を切り替え', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 追加
      notifier.toggleHideRetweets('acc_1');
      expect(notifier.state.hideRetweetsAccountIds.contains('acc_1'), true);

      // 削除
      notifier.toggleHideRetweets('acc_1');
      expect(notifier.state.hideRetweetsAccountIds.contains('acc_1'), false);
    });

    test('toggleHideRetweets で複数アカウントの管理', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.toggleHideRetweets('acc_1');
      notifier.toggleHideRetweets('acc_2');

      expect(notifier.state.hideRetweetsAccountIds, {'acc_1', 'acc_2'});

      notifier.toggleHideRetweets('acc_1');
      expect(notifier.state.hideRetweetsAccountIds, {'acc_2'});
    });

    test('toggleHideRetweets で SharedPreferences に保存される', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.toggleHideRetweets('acc_1');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      final savedList =
          prefs.getStringList('settings_hide_retweets_accounts');
      expect(savedList, contains('acc_1'));
    });

    test('isRetweetsHidden で正しい判定', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.isRetweetsHidden('acc_1'), false);

      notifier.toggleHideRetweets('acc_1');
      expect(notifier.isRetweetsHidden('acc_1'), true);

      notifier.toggleHideRetweets('acc_1');
      expect(notifier.isRetweetsHidden('acc_1'), false);
    });

    test('setShowAccountPicker で設定が変更される', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.setShowAccountPicker(true);
      expect(notifier.state.showAccountPickerOnEngagement, true);

      notifier.setShowAccountPicker(false);
      expect(notifier.state.showAccountPickerOnEngagement, false);
    });

    test('setShowAccountPicker で SharedPreferences に保存される', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.setShowAccountPicker(true);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_show_account_picker'), true);
    });

    test('startFetching で isFetchingActive が true になる', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.startFetching();
      expect(notifier.state.isFetchingActive, true);

      // クリーンアップ: スケジューラを停止
      notifier.stopFetching();
    });

    test('stopFetching で isFetchingActive が false になる', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.startFetching();
      expect(notifier.state.isFetchingActive, true);

      notifier.stopFetching();
      expect(notifier.state.isFetchingActive, false);
    });

    test('toggleFetching で isFetchingActive が切り替わる', () async {
      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.isFetchingActive, false);

      notifier.toggleFetching();
      expect(notifier.state.isFetchingActive, true);

      notifier.toggleFetching();
      expect(notifier.state.isFetchingActive, false);
    });

    test('_loadFromPrefs で保存済み値を復元', () async {
      SharedPreferences.setMockInitialValues({
        'settings_interval': 120,
        'settings_theme_mode': ThemeMode.dark.index,
        'settings_font_scale': 1.5,
        'settings_hide_retweets_accounts': ['acc_1', 'acc_2'],
        'settings_show_account_picker': true,
      });

      final notifier = SettingsNotifier();
      // _loadFromPrefs の完了を待つ
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(notifier.state.fetchIntervalSeconds, 120);
      expect(notifier.state.themeMode, ThemeMode.dark);
      expect(notifier.state.fontScale, 1.5);
      expect(notifier.state.hideRetweetsAccountIds, {'acc_1', 'acc_2'});
      expect(notifier.state.showAccountPickerOnEngagement, true);
    });

    test('_loadFromPrefs で不正な themeMode インデックスは clamp される', () async {
      SharedPreferences.setMockInitialValues({
        'settings_theme_mode': 99, // 不正な値
      });

      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // clamp(0, 2) で ThemeMode.values[2] = ThemeMode.dark
      expect(notifier.state.themeMode, ThemeMode.dark);
    });

    test('_loadFromPrefs で値がない場合はデフォルト値', () async {
      SharedPreferences.setMockInitialValues({});

      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(notifier.state.fetchIntervalSeconds, 60);
      expect(notifier.state.themeMode, ThemeMode.system);
      expect(notifier.state.fontScale, 1.0);
      expect(notifier.state.hideRetweetsAccountIds, isEmpty);
      expect(notifier.state.showAccountPickerOnEngagement, false);
    });

    test('_loadFromPrefs で負の themeMode インデックスは clamp される', () async {
      SharedPreferences.setMockInitialValues({
        'settings_theme_mode': -1, // 負の値
      });

      final notifier = SettingsNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // clamp(0, 2) で ThemeMode.values[0] = ThemeMode.system
      expect(notifier.state.themeMode, ThemeMode.system);
    });
  });
}
