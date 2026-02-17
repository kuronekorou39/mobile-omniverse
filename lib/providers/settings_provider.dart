import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sns_service.dart';
import '../services/scraping_scheduler.dart';

class SettingsState {
  const SettingsState({
    this.scrapingIntervalSeconds = 60,
    this.enabledServices = const {SnsService.x, SnsService.bluesky},
    this.isScrapingActive = false,
  });

  final int scrapingIntervalSeconds;
  final Set<SnsService> enabledServices;
  final bool isScrapingActive;

  SettingsState copyWith({
    int? scrapingIntervalSeconds,
    Set<SnsService>? enabledServices,
    bool? isScrapingActive,
  }) {
    return SettingsState(
      scrapingIntervalSeconds:
          scrapingIntervalSeconds ?? this.scrapingIntervalSeconds,
      enabledServices: enabledServices ?? this.enabledServices,
      isScrapingActive: isScrapingActive ?? this.isScrapingActive,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState());

  final _scheduler = ScrapingScheduler.instance;

  void setInterval(int seconds) {
    state = state.copyWith(scrapingIntervalSeconds: seconds);
    _scheduler.setInterval(Duration(seconds: seconds));
  }

  void toggleService(SnsService service) {
    final updated = Set<SnsService>.from(state.enabledServices);
    if (updated.contains(service)) {
      updated.remove(service);
      _scheduler.disableService(service);
    } else {
      updated.add(service);
      _scheduler.enableService(service);
    }
    state = state.copyWith(enabledServices: updated);
  }

  void startScraping() {
    for (final service in state.enabledServices) {
      _scheduler.enableService(service);
    }
    _scheduler.setInterval(Duration(seconds: state.scrapingIntervalSeconds));
    _scheduler.start();
    state = state.copyWith(isScrapingActive: true);
  }

  void stopScraping() {
    _scheduler.stop();
    state = state.copyWith(isScrapingActive: false);
  }

  void toggleScraping() {
    if (state.isScrapingActive) {
      stopScraping();
    } else {
      startScraping();
    }
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);
