import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/account.dart';
import '../services/debug_log_service.dart';
import '../services/x_features_service.dart';
import '../services/x_query_id_service.dart';

/// X の通知ページを WebView で開き、GraphQL の queryId を自動取得する
class NotificationWebViewScreen extends StatefulWidget {
  const NotificationWebViewScreen({super.key, required this.account, this.autoSave = false});

  final Account account;
  final bool autoSave;

  @override
  State<NotificationWebViewScreen> createState() =>
      _NotificationWebViewScreenState();
}

class _NotificationWebViewScreenState extends State<NotificationWebViewScreen> {
  double _progress = 0;
  bool _ready = false;
  bool _autoSaved = false;
  final Map<String, String> _capturedIds = {};
  InAppWebViewController? _controller;

  /// fetch を傍受して graphql リクエストの queryId を抽出する JS
  static const _interceptorScript = '''
(function() {
  window.__capturedQueryIds = {};
  var _origFetch = window.fetch;
  window.fetch = function() {
    var url = '';
    if (typeof arguments[0] === 'string') url = arguments[0];
    else if (arguments[0] && arguments[0].url) url = arguments[0].url;

    var match = url.match(/\\/i\\/api\\/graphql\\/([A-Za-z0-9_-]+)\\/([A-Za-z0-9_]+)/);
    if (match) {
      window.__capturedQueryIds[match[2]] = match[1];
    }
    return _origFetch.apply(this, arguments);
  };
})();
''';

  @override
  void initState() {
    super.initState();
    _setupCookies();
  }

  /// WebView のCookieを正しいアカウントに設定してからページを開く
  Future<void> _setupCookies() async {
    final creds = widget.account.xCredentials;
    final cookieManager = CookieManager.instance();

    // 全Cookie削除（他アカウントのセッションを排除）
    await cookieManager.deleteAllCookies();
    await InAppWebViewController.clearAllCache();

    // アカウントのCookieを設定
    final cookies = creds.cookieHeader.split('; ');
    for (final cookie in cookies) {
      final idx = cookie.indexOf('=');
      if (idx <= 0) continue;
      final name = cookie.substring(0, idx);
      final value = cookie.substring(idx + 1);
      await cookieManager.setCookie(
        url: WebUri('https://x.com'),
        name: name,
        value: value,
        domain: '.x.com',
        isSecure: true,
      );
    }

    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('通知 queryId 取得 (${widget.account.handle})'),
        actions: [
          TextButton.icon(
            onPressed: _onDone,
            icon: const Icon(Icons.check),
            label: Text('保存 (${_capturedIds.length})'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1.0 && _ready) LinearProgressIndicator(value: _progress),
          if (_capturedIds.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.green.withAlpha(30),
              child: Text(
                '取得済み: ${_capturedIds.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
                style: const TextStyle(fontSize: 11, color: Colors.green),
              ),
            ),
          Expanded(
            child: !_ready
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Cookie設定中…', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri('https://x.com/notifications'),
                    ),
                    initialSettings: InAppWebViewSettings(
                      userAgent:
                          'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
                          'AppleWebKit/537.36 (KHTML, like Gecko) '
                          'Chrome/131.0.0.0 Mobile Safari/537.36',
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      thirdPartyCookiesEnabled: true,
                    ),
                    initialUserScripts: UnmodifiableListView([
                      UserScript(
                        source: _interceptorScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                    ]),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                    },
                    onProgressChanged: (_, progress) {
                      setState(() => _progress = progress / 100);
                    },
                    onLoadStop: (controller, url) async {
                      // fetch interceptor を再注入（SPA遷移対応）
                      await controller.evaluateJavascript(source: _interceptorScript);
                      await Future.delayed(const Duration(seconds: 3));
                      await _collectCapturedIds(controller);
                    },
                    // ネイティブレベルでリソースURLを監視（JS interceptorより確実）
                    onLoadResource: (controller, resource) {
                      final url = resource.url?.toString() ?? '';
                      final match = RegExp(r'/i/api/graphql/([A-Za-z0-9_-]+)/([A-Za-z0-9_]+)').firstMatch(url);
                      if (match != null) {
                        final queryId = match.group(1)!;
                        final opName = match.group(2)!;
                        DebugLogService.instance.log(
                          'NotifWebView',
                          'captured: $opName = $queryId\nURL: $url',
                        );
                        if (_capturedIds[opName] != queryId) {
                          setState(() => _capturedIds[opName] = queryId);
                        }
                        // autoSave: NotificationsTimeline を取得したら自動保存して閉じる
                        if (widget.autoSave && opName == 'NotificationsTimeline' && !_autoSaved) {
                          _autoSaved = true;
                          Future.microtask(() => _onDone());
                        }
                        // features パラメータもキャプチャ
                        final uri = Uri.tryParse(url);
                        final featuresParam = uri?.queryParameters['features'];
                        if (featuresParam != null) {
                          try {
                            final features = json.decode(featuresParam) as Map<String, dynamic>;
                            XFeaturesService.instance.updateFeatures(opName, features);
                          } catch (_) {}
                        }
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _collectCapturedIds(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(
        source: 'JSON.stringify(window.__capturedQueryIds || {})',
      );
      if (result != null && result != 'null' && result != '{}') {
        final str = result is String ? result : result.toString();
        final regex = RegExp(r'"([^"]+)"\s*:\s*"([^"]+)"');
        bool changed = false;
        for (final match in regex.allMatches(str)) {
          final opName = match.group(1)!;
          final queryId = match.group(2)!;
          if (_capturedIds[opName] != queryId) {
            _capturedIds[opName] = queryId;
            changed = true;
          }
        }
        if (changed && mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('[NotifWebView] Error collecting queryIds: $e');
    }
  }

  Future<void> _onDone() async {
    // 最終キャプチャ
    if (_controller != null) {
      await _collectCapturedIds(_controller!);
    }

    if (_capturedIds.isNotEmpty) {
      final creds = widget.account.xCredentials;
      await XQueryIdService.instance.updateQueryIds(creds, _capturedIds);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_capturedIds.length}件の queryId を更新しました')),
        );
      }
    }

    // Cookie をクリア（他のWebView操作に影響しないように）
    await CookieManager.instance().deleteAllCookies();

    if (mounted) Navigator.of(context).pop(_capturedIds.isNotEmpty);
  }
}
