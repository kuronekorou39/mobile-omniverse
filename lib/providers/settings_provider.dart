import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/debug_log_service.dart';
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

/// センシティブコンテンツの表示モード
enum SensitiveMode {
  /// 全て表示（センシティブも隠さない）
  show,
  /// センシティブのみ隠す（デフォルト）
  hide,
  /// 全メディアを隠す
  hideAll,
}

/// FABの表示位置
enum FabPosition { right, left }
enum PostCardStyle { card, separator }

class SettingsState {
  const SettingsState({
    this.fetchIntervalSeconds = 15,
    this.isFetchingActive = true,
    this.themeMode = ThemeMode.system,
    this.fontScale = 0.8,
    this.hideRetweetsAccountIds = const {},
    this.showFetchTimer = true,
    this.sensitiveMode = SensitiveMode.hide,
    this.compactEngagement = true,
    this.imagePreviewSize = ImagePreviewSize.medium,
    this.hideUserInfo = false,
    this.fontFamily = '',
    this.appBarButtons = const {},
    this.fabPosition = FabPosition.right,
    this.postCardStyle = PostCardStyle.card,
    this.dripIntervalMs = 1500,
    this.debugLogEnabled = false,
    this.showPerfOverlay = false,
    this.imageCacheSize = 50,
    this.imageSaveFolder = 'Pictures/OmniVerse',
  });

  final int fetchIntervalSeconds;
  final bool isFetchingActive;
  final ThemeMode themeMode;
  final double fontScale;
  /// RT/リポストを非表示にするアカウント ID の集合
  final Set<String> hideRetweetsAccountIds;
  /// フェッチタイマーを表示するか
  final bool showFetchTimer;
  /// センシティブコンテンツの表示モード
  final SensitiveMode sensitiveMode;

  /// 後方互換: 既存コードの showSensitiveContent 参照用
  bool get showSensitiveContent => sensitiveMode == SensitiveMode.show;
  /// エンゲージメントバーをコンパクトにするか
  final bool compactEngagement;
  /// 画像プレビューサイズ
  final ImagePreviewSize imagePreviewSize;
  /// ユーザー情報（名前・アイコン）を非表示にするか
  final bool hideUserInfo;
  /// フォントファミリー（空文字=システムデフォルト）
  final String fontFamily;
  /// AppBarに表示するカスタムボタン
  final Set<String> appBarButtons;
  /// FABの表示位置
  final FabPosition fabPosition;
  final PostCardStyle postCardStyle;
  /// ドリップ間隔（ミリ秒）
  final int dripIntervalMs;
  /// デバッグログを記録するか
  final bool debugLogEnabled;
  /// パフォーマンスオーバーレイを表示するか
  final bool showPerfOverlay;
  /// 画像メモリキャッシュ上限枚数
  final int imageCacheSize;
  /// 画像保存先フォルダ（ストレージルートからの相対パス）
  final String imageSaveFolder;

  SettingsState copyWith({
    int? fetchIntervalSeconds,
    bool? isFetchingActive,
    ThemeMode? themeMode,
    double? fontScale,
    Set<String>? hideRetweetsAccountIds,
    bool? showFetchTimer,
    SensitiveMode? sensitiveMode,
    bool? compactEngagement,
    ImagePreviewSize? imagePreviewSize,
    bool? hideUserInfo,
    String? fontFamily,
    Set<String>? appBarButtons,
    FabPosition? fabPosition,
    PostCardStyle? postCardStyle,
    int? dripIntervalMs,
    bool? debugLogEnabled,
    bool? showPerfOverlay,
    int? imageCacheSize,
    String? imageSaveFolder,
  }) {
    return SettingsState(
      fetchIntervalSeconds: fetchIntervalSeconds ?? this.fetchIntervalSeconds,
      isFetchingActive: isFetchingActive ?? this.isFetchingActive,
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      hideRetweetsAccountIds: hideRetweetsAccountIds ?? this.hideRetweetsAccountIds,
      showFetchTimer: showFetchTimer ?? this.showFetchTimer,
      sensitiveMode: sensitiveMode ?? this.sensitiveMode,
      compactEngagement: compactEngagement ?? this.compactEngagement,
      imagePreviewSize: imagePreviewSize ?? this.imagePreviewSize,
      hideUserInfo: hideUserInfo ?? this.hideUserInfo,
      fontFamily: fontFamily ?? this.fontFamily,
      appBarButtons: appBarButtons ?? this.appBarButtons,
      fabPosition: fabPosition ?? this.fabPosition,
      postCardStyle: postCardStyle ?? this.postCardStyle,
      dripIntervalMs: dripIntervalMs ?? this.dripIntervalMs,
      debugLogEnabled: debugLogEnabled ?? this.debugLogEnabled,
      showPerfOverlay: showPerfOverlay ?? this.showPerfOverlay,
      imageCacheSize: imageCacheSize ?? this.imageCacheSize,
      imageSaveFolder: imageSaveFolder ?? this.imageSaveFolder,
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
  static const _keyShowFetchTimer = 'settings_show_fetch_timer';
  static const _keyShowSensitiveContent = 'settings_show_sensitive_content';
  static const _keyCompactEngagement = 'settings_compact_engagement';
  static const _keyImagePreviewSize = 'settings_image_preview_size';
  static const _keyHideUserInfo = 'settings_hide_user_info';
  static const _keyFontFamily = 'settings_font_family';
  static const _keyAppBarButtons = 'settings_appbar_buttons';

  final _scheduler = TimelineFetchScheduler.instance;

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final d = state; // デフォルト値の参照元（SettingsState コンストラクタの値）

    // センシティブモード: 旧bool値からの移行対応
    SensitiveMode? sensitiveMode;
    final sensitiveModeIndex = prefs.getInt('settings_sensitive_mode');
    if (sensitiveModeIndex != null) {
      sensitiveMode = SensitiveMode.values[sensitiveModeIndex.clamp(0, 2)];
    } else {
      final oldBool = prefs.getBool(_keyShowSensitiveContent);
      if (oldBool != null) {
        sensitiveMode = oldBool ? SensitiveMode.show : SensitiveMode.hide;
      }
    }

    // フォントファミリー: 旧システムフォント値をリセット
    var fontFamily = prefs.getString(_keyFontFamily);
    const legacyFonts = {'serif', 'monospace', 'sans-serif-condensed', 'cursive'};
    if (fontFamily != null && legacyFonts.contains(fontFamily)) {
      fontFamily = '';
      prefs.setString(_keyFontFamily, '');
    }

    state = state.copyWith(
      fetchIntervalSeconds: prefs.getInt(_keyInterval) ?? d.fetchIntervalSeconds,
      themeMode: ThemeMode.values[(prefs.getInt(_keyThemeMode) ?? d.themeMode.index).clamp(0, 2)],
      fontScale: prefs.getDouble(_keyFontScale) ?? d.fontScale,
      hideRetweetsAccountIds: prefs.getStringList(_keyHideRetweetsAccounts)?.toSet() ?? d.hideRetweetsAccountIds,
      showFetchTimer: prefs.getBool(_keyShowFetchTimer) ?? d.showFetchTimer,
      sensitiveMode: sensitiveMode ?? d.sensitiveMode,
      compactEngagement: prefs.getBool(_keyCompactEngagement) ?? d.compactEngagement,
      imagePreviewSize: ImagePreviewSize.values[(prefs.getInt(_keyImagePreviewSize) ?? d.imagePreviewSize.index).clamp(0, 2)],
      hideUserInfo: prefs.getBool(_keyHideUserInfo) ?? d.hideUserInfo,
      fontFamily: fontFamily ?? d.fontFamily,
      appBarButtons: prefs.getStringList(_keyAppBarButtons)?.toSet() ?? d.appBarButtons,
      fabPosition: FabPosition.values[(prefs.getInt('settings_fab_position') ?? d.fabPosition.index).clamp(0, 1)],
      postCardStyle: PostCardStyle.values[(prefs.getInt('settings_post_card_style') ?? d.postCardStyle.index).clamp(0, 1)],
      dripIntervalMs: prefs.getInt('settings_drip_interval_ms') ?? d.dripIntervalMs,
      debugLogEnabled: prefs.getBool('settings_debug_log_enabled') ?? d.debugLogEnabled,
      showPerfOverlay: prefs.getBool('settings_show_perf_overlay') ?? d.showPerfOverlay,
      imageCacheSize: prefs.getInt('settings_image_cache_size') ?? d.imageCacheSize,
      imageSaveFolder: prefs.getString('settings_image_save_folder') ?? d.imageSaveFolder,
    );

    // 画像キャッシュ上限を反映
    PaintingBinding.instance.imageCache.maximumSize = state.imageCacheSize;

    // デバッグログの有効/無効を反映
    DebugLogService.instance.enabled = state.debugLogEnabled;

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
    await prefs.setBool(_keyShowFetchTimer, state.showFetchTimer);
    await prefs.setInt('settings_sensitive_mode', state.sensitiveMode.index);
    await prefs.setBool(_keyCompactEngagement, state.compactEngagement);
    await prefs.setInt(_keyImagePreviewSize, state.imagePreviewSize.index);
    await prefs.setBool(_keyHideUserInfo, state.hideUserInfo);
    await prefs.setString(_keyFontFamily, state.fontFamily);
    await prefs.setStringList(_keyAppBarButtons, state.appBarButtons.toList());
    await prefs.setInt('settings_fab_position', state.fabPosition.index);
    await prefs.setInt('settings_post_card_style', state.postCardStyle.index);
    await prefs.setInt('settings_drip_interval_ms', state.dripIntervalMs);
    await prefs.setBool('settings_debug_log_enabled', state.debugLogEnabled);
    await prefs.setBool('settings_show_perf_overlay', state.showPerfOverlay);
    await prefs.setInt('settings_image_cache_size', state.imageCacheSize);
    await prefs.setString('settings_image_save_folder', state.imageSaveFolder);
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

  void setShowFetchTimer(bool value) {
    state = state.copyWith(showFetchTimer: value);
    _saveToPrefs();
  }

  void setSensitiveMode(SensitiveMode mode) {
    state = state.copyWith(sensitiveMode: mode);
    _saveToPrefs();
  }

  void cycleSensitiveMode() {
    final next = SensitiveMode.values[
        (state.sensitiveMode.index + 1) % SensitiveMode.values.length];
    setSensitiveMode(next);
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

  void setImageSaveFolder(String value) {
    state = state.copyWith(imageSaveFolder: value);
    _saveToPrefs();
  }

  void setDebugLogEnabled(bool value) {
    state = state.copyWith(debugLogEnabled: value);
    DebugLogService.instance.enabled = value;
    _saveToPrefs();
  }

  void setShowPerfOverlay(bool value) {
    state = state.copyWith(showPerfOverlay: value);
    _saveToPrefs();
  }

  void setImageCacheSize(int value) {
    state = state.copyWith(imageCacheSize: value);
    PaintingBinding.instance.imageCache.maximumSize = value;
    _saveToPrefs();
  }

  void setDripIntervalMs(int ms) {
    state = state.copyWith(dripIntervalMs: ms);
    _saveToPrefs();
  }

  void setFabPosition(FabPosition position) {
    state = state.copyWith(fabPosition: position);
    _saveToPrefs();
  }

  void setPostCardStyle(PostCardStyle style) {
    state = state.copyWith(postCardStyle: style);
    _saveToPrefs();
  }

  void toggleAppBarButton(String buttonId) {
    final current = Set<String>.from(state.appBarButtons);
    if (current.contains(buttonId)) {
      current.remove(buttonId);
    } else {
      current.add(buttonId);
    }
    state = state.copyWith(appBarButtons: current);
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
