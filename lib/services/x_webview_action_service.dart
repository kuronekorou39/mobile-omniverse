import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/account.dart';

/// X の CDN が x-client-transaction-id を暗号学的に検証するエンドポイント
/// (CreateRetweet, DeleteRetweet 等) を、隠し WebView 経由で実行するサービス。
/// WebView はブラウザとして正規のヘッダーを自動生成するため、検証を通過できる。
class XWebViewActionService {
  XWebViewActionService._();
  static final instance = XWebViewActionService._();

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  bool _isReady = false;
  final _readyCompleter = Completer<void>();

  /// WebView を初期化 (x.com にアクセスして Cookie を設定)
  Future<void> init(XCredentials creds) async {
    if (_isReady) return;

    // Cookie を設定
    final cookieManager = CookieManager.instance();
    final cookies = creds.allCookies.split('; ');
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
      );
    }

    _webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('https://x.com')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent:
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ),
      onLoadStop: (controller, url) {
        _controller = controller;
        if (!_isReady) {
          _isReady = true;
          if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        }
      },
    );

    await _webView!.run();

    // 最大 15 秒待機
    await _readyCompleter.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint('[XWebView] Timeout waiting for page load');
      },
    );
  }

  /// WebView 内の fetch() でリツイート
  Future<({bool success, int statusCode, String body})> retweet(
      XCredentials creds, String tweetId) async {
    return _executeMutation(creds, 'ojPdsZsimiJrUGLR1sjUtA', 'CreateRetweet', {
      'tweet_id': tweetId,
      'dark_request': false,
    });
  }

  /// WebView 内の fetch() でリツイート解除
  Future<({bool success, int statusCode, String body})> unretweet(
      XCredentials creds, String tweetId) async {
    return _executeMutation(
        creds, 'iQtK4dl5hBmXewYZuEOKVw', 'DeleteRetweet', {
      'source_tweet_id': tweetId,
      'dark_request': false,
    });
  }

  Future<({bool success, int statusCode, String body})> _executeMutation(
    XCredentials creds,
    String queryId,
    String operationName,
    Map<String, dynamic> variables,
  ) async {
    if (_controller == null) {
      await init(creds);
    }
    if (_controller == null) {
      return (success: false, statusCode: 0, body: 'WebView not ready');
    }

    final variablesJson = json.encode(variables);
    final ct0 = creds.ct0;

    final js = '''
      (async function() {
        try {
          var queryId = "$queryId";
          var url = "https://x.com/i/api/graphql/" + queryId + "/$operationName";
          var body = JSON.stringify({
            variables: $variablesJson,
            queryId: queryId
          });
          var resp = await fetch(url, {
            method: "POST",
            headers: {
              "Authorization": "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA",
              "Content-Type": "application/json",
              "x-csrf-token": "$ct0",
              "x-twitter-auth-type": "OAuth2Session",
              "x-twitter-active-user": "yes",
              "x-twitter-client-language": "ja"
            },
            credentials: "include"
          });
          var text = await resp.text();
          return JSON.stringify({status: resp.status, body: text});
        } catch(e) {
          return JSON.stringify({status: 0, body: e.toString()});
        }
      })()
    ''';

    try {
      final result = await _controller!.evaluateJavascript(source: js);
      debugPrint('[XWebView] $operationName raw result: $result');

      if (result == null) {
        return (success: false, statusCode: 0, body: 'null result');
      }

      final parsed =
          json.decode(result is String ? result : result.toString())
              as Map<String, dynamic>;
      final statusCode = parsed['status'] as int? ?? 0;
      final body = parsed['body'] as String? ?? '';

      debugPrint('[XWebView] $operationName $tweetId: $statusCode');
      debugPrint(
          '[XWebView] $operationName body: ${body.length > 200 ? body.substring(0, 200) : body}');

      return (success: statusCode == 200, statusCode: statusCode, body: body);
    } catch (e) {
      debugPrint('[XWebView] $operationName error: $e');
      return (success: false, statusCode: 0, body: e.toString());
    }
  }

  String get tweetId => ''; // unused, needed for log label

  void dispose() {
    _webView?.dispose();
    _webView = null;
    _controller = null;
    _isReady = false;
  }
}
