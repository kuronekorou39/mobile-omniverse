import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sns_service.dart';
import '../services/cookie_persistence_service.dart';
import '../services/webview_manager.dart';

class WebViewTabScreen extends ConsumerStatefulWidget {
  const WebViewTabScreen({super.key, required this.service});

  final SnsService service;

  @override
  ConsumerState<WebViewTabScreen> createState() => _WebViewTabScreenState();
}

class _WebViewTabScreenState extends ConsumerState<WebViewTabScreen>
    with AutomaticKeepAliveClientMixin {
  InAppWebViewController? _controller;
  double _progress = 0;
  String _currentUrl = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    WebViewManager.instance.unregisterController(widget.service);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        if (_progress < 1.0) LinearProgressIndicator(value: _progress),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => _controller?.goBack(),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => _controller?.reload(),
              ),
              Expanded(
                child: Text(
                  _currentUrl,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.home, size: 20),
                onPressed: () => _controller?.loadUrl(
                  urlRequest:
                      URLRequest(url: WebUri(widget.service.homeUrl)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest:
                URLRequest(url: WebUri(widget.service.homeUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              userAgent:
                  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              // Register controller so scraper can use it directly
              WebViewManager.instance
                  .registerController(widget.service, controller);
            },
            onLoadStart: (controller, url) {
              setState(() {
                _currentUrl = url?.toString() ?? '';
              });
            },
            onProgressChanged: (controller, progress) {
              setState(() {
                _progress = progress / 100;
              });
            },
            onLoadStop: (controller, url) async {
              setState(() {
                _progress = 1.0;
                _currentUrl = url?.toString() ?? '';
              });
              await CookiePersistenceService.instance
                  .saveCookies(widget.service);
            },
          ),
        ),
      ],
    );
  }
}
