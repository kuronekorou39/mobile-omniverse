import 'dart:async';

import '../models/sns_service.dart';
import 'webview_manager.dart';

class ScrapingScheduler {
  ScrapingScheduler._();
  static final instance = ScrapingScheduler._();

  Timer? _timer;
  Duration _interval = const Duration(seconds: 60);
  final Set<SnsService> _enabledServices = {};
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  Duration get interval => _interval;
  Set<SnsService> get enabledServices => Set.unmodifiable(_enabledServices);

  void setInterval(Duration interval) {
    _interval = interval;
    if (_isRunning) {
      stop();
      start();
    }
  }

  void enableService(SnsService service) {
    _enabledServices.add(service);
  }

  void disableService(SnsService service) {
    _enabledServices.remove(service);
  }

  bool isServiceEnabled(SnsService service) =>
      _enabledServices.contains(service);

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _scrapeAll();
    _timer = Timer.periodic(_interval, (_) => _scrapeAll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  Future<void> _scrapeAll() async {
    final manager = WebViewManager.instance;
    for (final service in _enabledServices) {
      await manager.scrape(service);
    }
  }

  Future<void> scrapeNow() async {
    await _scrapeAll();
  }
}
