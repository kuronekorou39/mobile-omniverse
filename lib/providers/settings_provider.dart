import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/timeline_fetch_scheduler.dart';

/// 画像プレビューサイズ
enum ImagePreviewSize {
  small('小'),
  medium('中'),
  large('大');

  const ImagePreviewSize(this.label);
  final String label;

  double get singleImageMaxHeight => switch (this) {
        small => 150,
        medium => 200,
        large => 300,
      };
  double get gridImageHeight => switch (this) {
        small => 80,
        medium => 100,
        large => 150,
      };
  double get videoHeight => switch (this) {
        small => 120,
        medium => 150,
        large => 200,
      };
}

class SettingsState {
  const SettingsState({
    this.fetchIntervalSeconds = 15,
    this.isFetchingActive = true,
    this.themeMode = ThemeMode.system,
    this.fontScale = 1.0,
    this.hideRetweetsAccountIds = const {},
    this.showAccountPickerOnEngagement = false,
    this.showFetchTimer = true,
    this.showSensitiveContent = false,
    this.compactEngagement = true,
    this.imagePreviewSize = ImagePreviewSize.medium,
    this.hideUserInfo = false,
    this.fontFamily = '',
  });

  final int fetchIntervalSeconds;
  final bool isFetchingActive;
  final ThemeMode themeMode;
  final double fontScale;
  /// RT/リポストを非表示にするアカウント ID の集合
  final Set<String> hideRetweetsAccountIds;
  /// いいね/RT 時にアカウント選択モーダルを表示するか
  final bool showAccountPickerOnEngagement;
  /// フェッチタイマーを表示するか
  final bool showFetchTimer;
  /// センシティブコンテンツを常に表示するか
  final bool showSensitiveContent;
  /// エンゲージメントバーをコンパクトにするか
  final bool compactEngagement;
  /// 画像プレビューサイズ
  final ImagePreviewSize imagePreviewSize;
  /// ユーザー情報（名前・アイコン）を非表示にするか
  final bool hideUserInfo;
  /// フォントファミリー（空文字=システムデフォルト）
  final String fontFamily;

  SettingsState copyWith({
    int? fetchIntervalSeconds,
    bool? isFetchingActive,
    ThemeMode? themeMode,
    double? fontScale,
    Set<String>? hideRetweetsAccountIds,
    bool? showAccountPickerOnEngagement,
    bool? showFetchTimer,
    bool? showSensitiveContent,
    bool? compactEngagement,
    ImagePreviewSize? imagePreviewSize,
    bool? hideUserInfo,
    String? fontFamily,
  }) {
    return SettingsState(
      fetchIntervalSeconds: fetchIntervalSeconds ?? this.fetchIntervalSeconds,
      isFetchingActive: isFetchingActive ?? this.isFetchingActive,
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      hideRetweetsAccountIds: hideRetweetsAccountIds ?? this.hideRetweetsAccountIds,
      showAccountPickerOnEngagement: showAccountPickerOnEngagement ?? this.showAccountPickerOnEngagement,
      showFetchTimer: showFetchTimer ?? this.showFetchTimer,
      showSensitiveContent: showSensitiveContent ?? this.showSensitiveContent,
      compactEngagement: compactEngagement ?? this.compactEngagement,
      imagePreviewSize: imagePreviewSize ?? this.imagePreviewSize,
      hideUserInfo: hideUserInfo ?? this.hideUserInfo,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _loadFromPrefs();
  }

  static const _keyInterval = 'settings_interval';
  static const _keyThemeMode = 'settings_theme_mode';
  static const _keyFontScale = 'settings_font_scale';
  static const _keyHideRetweetsAccounts = 'settings_hide_retweets_accounts';
  static const _keyShowAccountPicker = 'settings_show_account_picker';
  static const _keyShowFetchTimer = 'settings_show_fetch_timer';
  static const _keyShowSensitiveContent = 'settings_show_sensitive_content';
  static const _keyCompactEngagement = 'settings_compact_engagement';
  static const _keyImagePreviewSize = 'settings_image_preview_size';
  static const _keyHideUserInfo = 'settings_hide_user_info';
  static const _keyFontFamily = 'settings_font_family';

  final _scheduler = TimelineFetchScheduler.instance;

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt(_keyInterval) ?? 15;
    final themeModeIndex = prefs.getInt(_keyThemeMode) ?? 0;
    final fontScale = prefs.getDouble(_keyFontScale) ?? 1.0;
    final hideRtList = prefs.getStringList(_keyHideRetweetsAccounts) ?? [];
    final showAccountPicker = prefs.getBool(_keyShowAccountPicker) ?? false;
    final showFetchTimer = prefs.getBool(_keyShowFetchTimer) ?? true;
    final showSensitiveContent = prefs.getBool(_keyShowSensitiveContent) ?? false;
    final compactEngagement = prefs.getBool(_keyCompactEngagement) ?? true;
    final imagePreviewSizeIndex = prefs.getInt(_keyImagePreviewSize) ?? ImagePreviewSize.medium.index;
    final hideUserInfo = prefs.getBool(_keyHideUserInfo) ?? false;
    final fontFamily = prefs.getString(_keyFontFamily) ?? '';

    state = state.copyWith(
      fetchIntervalSeconds: interval,
      themeMode: ThemeMode.values[themeModeIndex.clamp(0, 2)],
      fontScale: fontScale,
      hideRetweetsAccountIds: hideRtList.toSet(),
      showAccountPickerOnEngagement: showAccountPicker,
      showFetchTimer: showFetchTimer,
      showSensitiveContent: showSensitiveContent,
      compactEngagement: compactEngagement,
      imagePreviewSize: ImagePreviewSize.values[imagePreviewSizeIndex.clamp(0, 2)],
      hideUserInfo: hideUserInfo,
      fontFamily: fontFamily,
    );

    // #3: デフォルトフェッチONの場合、起動時にスケジューラを開始
    if (state.isFetchingActive) {
      startFetching();
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyInterval, state.fetchIntervalSeconds);
    await prefs.setInt(_keyThemeMode, state.themeMode.index);
    await prefs.setDouble(_keyFontScale, state.fontScale);
    await prefs.setStringList(
        _keyHideRetweetsAccounts, state.hideRetweetsAccountIds.toList());
    await prefs.setBool(
        _keyShowAccountPicker, state.showAccountPickerOnEngagement);
    await prefs.setBool(_keyShowFetchTimer, state.showFetchTimer);
    await prefs.setBool(_keyShowSensitiveContent, state.showSensitiveContent);
    await prefs.setBool(_keyCompactEngagement, state.compactEngagement);
    await prefs.setInt(_keyImagePreviewSize, state.imagePreviewSize.index);
    await prefs.setBool(_keyHideUserInfo, state.hideUserInfo);
    await prefs.setString(_keyFontFamily, state.fontFamily);
  }

  void setInterval(int seconds) {
    state = state.copyWith(fetchIntervalSeconds: seconds);
    _scheduler.setInterval(Duration(seconds: seconds));
    _saveToPrefs();
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _saveToPrefs();
  }

  void setFontScale(double scale) {
    state = state.copyWith(fontScale: scale);
    _saveToPrefs();
  }

  void toggleHideRetweets(String accountId) {
    final current = Set<String>.from(state.hideRetweetsAccountIds);
    if (current.contains(accountId)) {
      current.remove(accountId);
    } else {
      current.add(accountId);
    }
    state = state.copyWith(hideRetweetsAccountIds: current);
    _saveToPrefs();
  }

  bool isRetweetsHidden(String accountId) {
    return state.hideRetweetsAccountIds.contains(accountId);
  }

  void setShowAccountPicker(bool value) {
    state = state.copyWith(showAccountPickerOnEngagement: value);
    _saveToPrefs();
  }

  void setShowFetchTimer(bool value) {
    state = state.copyWith(showFetchTimer: value);
    _saveToPrefs();
  }

  void setShowSensitiveContent(bool value) {
    state = state.copyWith(showSensitiveContent: value);
    _saveToPrefs();
  }

  void setCompactEngagement(bool value) {
    state = state.copyWith(compactEngagement: value);
    _saveToPrefs();
  }

  void setImagePreviewSize(ImagePreviewSize size) {
    state = state.copyWith(imagePreviewSize: size);
    _saveToPrefs();
  }

  void setHideUserInfo(bool value) {
    state = state.copyWith(hideUserInfo: value);
    _saveToPrefs();
  }

  void setFontFamily(String value) {
    state = state.copyWith(fontFamily: value);
    _saveToPrefs();
  }

  void startFetching() {
    _scheduler.setInterval(Duration(seconds: state.fetchIntervalSeconds));
    _scheduler.start();
    state = state.copyWith(isFetchingActive: true);
  }

  void stopFetching() {
    _scheduler.stop();
    state = state.copyWith(isFetchingActive: false);
  }

  void toggleFetching() {
    if (state.isFetchingActive) {
      stopFetching();
    } else {
      startFetching();
    }
  }

  /// アプリがバックグラウンドに入った時の一時停止（設定は変えない）
  void pauseFetching() {
    _scheduler.stop();
  }

  /// アプリがフォアグラウンドに戻った時の再開
  void resumeFetching() {
    if (state.isFetchingActive && !_scheduler.isRunning) {
      _scheduler.setInterval(Duration(seconds: state.fetchIntervalSeconds));
      _scheduler.start();
    }
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);
