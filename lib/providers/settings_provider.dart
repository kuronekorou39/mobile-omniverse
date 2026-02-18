import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/timeline_fetch_scheduler.dart';

class SettingsState {
  const SettingsState({
    this.fetchIntervalSeconds = 60,
    this.isFetchingActive = false,
  });

  final int fetchIntervalSeconds;
  final bool isFetchingActive;

  SettingsState copyWith({
    int? fetchIntervalSeconds,
    bool? isFetchingActive,
  }) {
    return SettingsState(
      fetchIntervalSeconds: fetchIntervalSeconds ?? this.fetchIntervalSeconds,
      isFetchingActive: isFetchingActive ?? this.isFetchingActive,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState());

  final _scheduler = TimelineFetchScheduler.instance;

  void setInterval(int seconds) {
    state = state.copyWith(fetchIntervalSeconds: seconds);
    _scheduler.setInterval(Duration(seconds: seconds));
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
