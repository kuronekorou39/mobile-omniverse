import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/account.dart';

/// ブラウザ投稿のリクエストをキャプチャするデバッグ画面
/// WebView で x.com/compose/post を開き、fetch をインターセプトして
/// CreateTweet リクエストの全ヘッダー・Cookie・ボディをキャプチャする
class BrowserPostDebugScreen extends StatefulWidget {
  const BrowserPostDebugScreen({super.key, required this.account});

  final Account account;

  @override
  State<BrowserPostDebugScreen> createState() =>
      _BrowserPostDebugScreenState();
}

class _BrowserPostDebugScreenState extends State<BrowserPostDebugScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _cookiesReady = false;
  final List<String> _capturedRequests = [];

  @override
  void initState() {
    super.initState();
    _prepareCookies();
  }

  Future<void> _prepareCookies() async {
    final cookieManager = CookieManager.instance();
    await cookieManager.deleteAllCookies();
    await InAppWebViewController.clearAllCache();

    final creds = widget.account.xCredentials;
    final cookieStr = creds.allCookies;
    if (cookieStr.isNotEmpty) {
      final pairs = cookieStr.split('; ');
      for (final pair in pairs) {
        final eqIdx = pair.indexOf('=');
        if (eqIdx <= 0) continue;
        final name = pair.substring(0, eqIdx).trim();
        final value = pair.substring(eqIdx + 1).trim();
        if (name.isEmpty) continue;
        await cookieManager.setCookie(
          url: WebUri('https://x.com'),
          name: name,
          value: value,
          domain: '.x.com',
          path: '/',
        );
      }
    }

    if (mounted) {
      setState(() => _cookiesReady = true);
    }
  }

  /// fetch / XMLHttpRequest をインターセプトして API リクエストをキャプチャする JS
  static const _interceptorScript = '''
(function() {
  // キャプチャ結果を格納
  window.__capturedApiRequests = [];

  // --- fetch インターセプト ---
  var _origFetch = window.fetch;
  window.fetch = function(input, init) {
    var url = '';
    if (typeof input === 'string') {
      url = input;
    } else if (input && input.url) {
      url = input.url;
    }

    // graphql API コールのみキャプチャ
    if (url.indexOf('/i/api/graphql/') !== -1 || url.indexOf('/i/api/') !== -1) {
      var method = (init && init.method) ? init.method : 'GET';
      var headers = {};
      if (init && init.headers) {
        if (init.headers instanceof Headers) {
          init.headers.forEach(function(value, key) {
            headers[key] = value;
          });
        } else if (typeof init.headers === 'object') {
          headers = Object.assign({}, init.headers);
        }
      }
      var body = (init && init.body) ? init.body : null;
      var cookies = document.cookie;

      var captureEntry = {
        timestamp: new Date().toISOString(),
        url: url,
        method: method,
        headers: headers,
        cookies: cookies,
        body: body,
        response: null
      };

      return _origFetch.apply(this, arguments).then(function(response) {
        return response.clone().text().then(function(respText) {
          captureEntry.response = {
            status: response.status,
            statusText: response.statusText,
            body: respText.substring(0, 2000)
          };
          // レスポンスヘッダーもキャプチャ
          var respHeaders = {};
          response.headers.forEach(function(value, key) {
            respHeaders[key] = value;
          });
          captureEntry.response.headers = respHeaders;

          window.__capturedApiRequests.push(captureEntry);

          // CreateTweet の場合は即通知
          if (url.indexOf('CreateTweet') !== -1) {
            window.flutter_inappwebview.callHandler('onCreateTweet',
              JSON.stringify(captureEntry));
          }
          return response;
        });
      }).catch(function(err) {
        captureEntry.response = { error: err.toString() };
        window.__capturedApiRequests.push(captureEntry);
        throw err;
      });
    }

    return _origFetch.apply(this, arguments);
  };

  // --- XMLHttpRequest インターセプト ---
  var _origXHROpen = XMLHttpRequest.prototype.open;
  var _origXHRSend = XMLHttpRequest.prototype.send;
  var _origXHRSetHeader = XMLHttpRequest.prototype.setRequestHeader;

  XMLHttpRequest.prototype.open = function(method, url) {
    this.__captureUrl = url;
    this.__captureMethod = method;
    this.__captureHeaders = {};
    return _origXHROpen.apply(this, arguments);
  };

  XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
    if (this.__captureHeaders) {
      this.__captureHeaders[name] = value;
    }
    return _origXHRSetHeader.apply(this, arguments);
  };

  XMLHttpRequest.prototype.send = function(body) {
    var self = this;
    var url = self.__captureUrl || '';
    if (url.indexOf('/i/api/graphql/') !== -1 || url.indexOf('/i/api/') !== -1) {
      var captureEntry = {
        timestamp: new Date().toISOString(),
        url: url,
        method: self.__captureMethod || 'GET',
        headers: self.__captureHeaders || {},
        cookies: document.cookie,
        body: body,
        transport: 'XHR',
        response: null
      };

      self.addEventListener('load', function() {
        captureEntry.response = {
          status: self.status,
          statusText: self.statusText,
          body: (self.responseText || '').substring(0, 2000)
        };
        window.__capturedApiRequests.push(captureEntry);

        if (url.indexOf('CreateTweet') !== -1) {
          window.flutter_inappwebview.callHandler('onCreateTweet',
            JSON.stringify(captureEntry));
        }
      });
    }
    return _origXHRSend.apply(this, arguments);
  };

  console.log('[OmniDebug] fetch/XHR interceptor installed');
})();
''';

  void _showCapturedRequest(String jsonStr) {
    if (!mounted) return;
    setState(() {
      _capturedRequests.add(jsonStr);
    });

    // ダイアログで表示
    _showRequestDialog(jsonStr);
  }

  void _showRequestDialog(String jsonStr) {
    try {
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final buf = StringBuffer();

      buf.writeln('=== ${data['method']} ${data['url']} ===');
      buf.writeln('Time: ${data['timestamp']}');
      if (data['transport'] != null) buf.writeln('Transport: ${data['transport']}');
      buf.writeln();

      buf.writeln('=== Request Headers (JS側で設定) ===');
      final headers = data['headers'] as Map<String, dynamic>? ?? {};
      for (final entry in headers.entries) {
        buf.writeln('${entry.key}: ${entry.value}');
      }
      buf.writeln();

      buf.writeln('=== Cookies (document.cookie) ===');
      final cookies = data['cookies'] as String? ?? '';
      for (final pair in cookies.split('; ')) {
        buf.writeln(pair);
      }
      buf.writeln();

      buf.writeln('=== Request Body ===');
      final body = data['body'];
      if (body is String && body.isNotEmpty) {
        try {
          final parsed = json.decode(body);
          buf.writeln(const JsonEncoder.withIndent('  ').convert(parsed));
        } catch (_) {
          buf.writeln(body);
        }
      } else {
        buf.writeln('(empty)');
      }
      buf.writeln();

      final resp = data['response'] as Map<String, dynamic>?;
      if (resp != null) {
        buf.writeln('=== Response ===');
        buf.writeln('Status: ${resp['status']} ${resp['statusText'] ?? ''}');
        if (resp['headers'] != null) {
          buf.writeln('--- Response Headers ---');
          final rh = resp['headers'] as Map<String, dynamic>;
          for (final e in rh.entries) {
            buf.writeln('${e.key}: ${e.value}');
          }
        }
        buf.writeln('--- Response Body ---');
        final respBody = resp['body'] as String? ?? '';
        if (respBody.isNotEmpty) {
          try {
            final parsed = json.decode(respBody);
            buf.writeln(const JsonEncoder.withIndent('  ').convert(parsed));
          } catch (_) {
            buf.writeln(respBody);
          }
        }
      }

      final fullText = buf.toString();

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CreateTweet キャプチャ'),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('コピー'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fullText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('コピーしました')),
                        );
                      },
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      fullText,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('[BrowserDebug] Error parsing capture: $e');
    }
  }

  Future<void> _showAllCaptures() async {
    if (_controller == null) return;

    final result = await _controller!.evaluateJavascript(
      source: 'JSON.stringify(window.__capturedApiRequests || [])',
    );

    if (result == null || result == 'null' || result == '[]') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('キャプチャされたリクエストはありません')),
        );
      }
      return;
    }

    final list = json.decode(result.toString()) as List<dynamic>;
    if (list.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('キャプチャされたリクエストはありません')),
        );
      }
      return;
    }

    if (!mounted) return;

    // 全リクエスト一覧をダイアログで表示
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('キャプチャ済み (${list.length}件)'),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, index) {
              final item = list[index] as Map<String, dynamic>;
              final url = item['url'] as String? ?? '';
              final method = item['method'] as String? ?? '';
              final status = item['response']?['status'] ?? '?';
              // URL の最後のパス部分を表示
              final shortUrl = url.split('/').last.split('?').first;
              return ListTile(
                dense: true,
                title: Text(
                  '$method $shortUrl ($status)',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  item['timestamp'] as String? ?? '',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showRequestDialog(json.encode(item));
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final allText = list
                  .map((e) => const JsonEncoder.withIndent('  ').convert(e))
                  .join('\n\n---\n\n');
              Clipboard.setData(ClipboardData(text: allText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('全件コピーしました')),
              );
            },
            child: const Text('全件コピー'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ブラウザ投稿 (${widget.account.handle})'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            await CookieManager.instance().deleteAllCookies();
            if (mounted) Navigator.of(context).pop();
          },
        ),
        actions: [
          if (_capturedRequests.isNotEmpty)
            Badge(
              label: Text('${_capturedRequests.length}'),
              child: IconButton(
                icon: const Icon(Icons.bug_report),
                tooltip: 'キャプチャ一覧',
                onPressed: _showAllCaptures,
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: 'キャプチャ一覧',
              onPressed: _showAllCaptures,
            ),
        ],
      ),
      body: Column(
        children: [
          // ステータスバー
          Container(
            width: double.infinity,
            color: Colors.amber.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'ブラウザから普通に投稿してください。'
              'CreateTweet リクエストを自動キャプチャします。'
              '${_capturedRequests.isNotEmpty ? ' (${_capturedRequests.length}件キャプチャ済み)' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (_progress < 1.0) LinearProgressIndicator(value: _progress),
          // ナビゲーション
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _controller?.goBack(),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _controller?.goForward(),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _controller?.reload(),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  _controller?.loadUrl(
                    urlRequest: URLRequest(
                      url: WebUri('https://x.com/compose/post'),
                    ),
                  );
                },
                child: const Text('投稿画面へ'),
              ),
            ],
          ),
          Expanded(
            child: !_cookiesReady
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri('https://x.com/home'),
                    ),
                    initialSettings: InAppWebViewSettings(
                      userAgent:
                          'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
                          'AppleWebKit/537.36 (KHTML, like Gecko) '
                          'Chrome/120.0.0.0 Mobile Safari/537.36',
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      thirdPartyCookiesEnabled: true,
                    ),
                    shouldOverrideUrlLoading:
                        (controller, navigationAction) async {
                      return NavigationActionPolicy.ALLOW;
                    },
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      // JS → Dart ハンドラー登録
                      controller.addJavaScriptHandler(
                        handlerName: 'onCreateTweet',
                        callback: (args) {
                          if (args.isNotEmpty) {
                            _showCapturedRequest(args[0].toString());
                          }
                        },
                      );
                    },
                    onProgressChanged: (_, progress) {
                      setState(() => _progress = progress / 100);
                    },
                    onLoadStop: (controller, url) {
                      debugPrint('[BrowserDebug] onLoadStop: $url');
                      final urlStr = url?.toString() ?? '';
                      if (urlStr.contains('x.com')) {
                        // インターセプターを注入（ページ遷移のたびに再注入）
                        controller.evaluateJavascript(
                          source: _interceptorScript,
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
