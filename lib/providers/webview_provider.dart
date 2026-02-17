import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sns_service.dart';
import '../services/webview_manager.dart';

class WebViewState {
  const WebViewState({
    this.registeredServices = const {},
  });

  final Set<SnsService> registeredServices;

  WebViewState copyWith({Set<SnsService>? registeredServices}) {
    return WebViewState(
      registeredServices: registeredServices ?? this.registeredServices,
    );
  }
}

class WebViewNotifier extends StateNotifier<WebViewState> {
  WebViewNotifier() : super(const WebViewState());

  bool isRegistered(SnsService service) =>
      WebViewManager.instance.hasController(service);
}

final webViewProvider =
    StateNotifierProvider<WebViewNotifier, WebViewState>(
  (ref) => WebViewNotifier(),
);
