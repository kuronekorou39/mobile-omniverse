import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/timeline_fetch_scheduler.dart';

class SettingsState {
  const SettingsState({
    this.fetchIntervalSeconds = 60,
    this.isFetchingActive = false,
    this.themeMode = ThemeMode.system,
    this.fontScale = 1.0,
  });

  final int fetchIntervalSeconds;
  final bool isFetchingActive;
  final ThemeMode themeMode;
  final double fontScale;

  SettingsState copyWith({
    int? fetchIntervalSeconds,
    bool? isFetchingActive,
    ThemeMode? themeMode,
    double? fontScale,
  }) {
    return SettingsState(
      fetchIntervalSeconds: fetchIntervalSeconds ?? this.fetchIntervalSeconds,
      isFetchingActive: isFetchingActive ?? this.isFetchingActive,
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
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

  final _scheduler = TimelineFetchScheduler.instance;

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt(_keyInterval) ?? 60;
    final themeModeIndex = prefs.getInt(_keyThemeMode) ?? 0;
    final fontScale = prefs.getDouble(_keyFontScale) ?? 1.0;

    state = state.copyWith(
      fetchIntervalSeconds: interval,
      themeMode: ThemeMode.values[themeModeIndex.clamp(0, 2)],
      fontScale: fontScale,
    );
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyInterval, state.fetchIntervalSeconds);
    await prefs.setInt(_keyThemeMode, state.themeMode.index);
    await prefs.setDouble(_keyFontScale, state.fontScale);
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
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);
