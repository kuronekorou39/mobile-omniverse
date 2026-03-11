import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/account.dart';
import 'x_features.dart';
import 'x_query_id_service.dart';

/// X の CDN が x-client-transaction-id を暗号学的に検証するエンドポイント
/// (CreateTweet, CreateRetweet, DeleteRetweet 等) を、隠し WebView 経由で実行するサービス。
/// WebView はブラウザとして正規のヘッダーを自動生成するため、検証を通過できる。
class XWebViewActionService {
  XWebViewActionService._();
  static final instance = XWebViewActionService._();

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  bool _isReady = false;
  Completer<void>? _readyCompleter;
  String? _currentAuthToken; // 現在初期化中のアカウント

  /// WebView を初期化 (x.com にアクセスして Cookie を設定)
  /// アカウントが変わった場合は再初期化する
  Future<void> init(XCredentials creds) async {
    // 同一アカウントで初期化済みならスキップ
    if (_isReady && _currentAuthToken == creds.authToken) return;

    // 別アカウント or 未初期化 → 再初期化
    if (_isReady || _webView != null) {
      dispose();
    }

    _currentAuthToken = creds.authToken;
    _readyCompleter = Completer<void>();
    debugPrint('[XWebView] init: clearing old cookies, setting new ones');

    // 前アカウントの Cookie を完全クリアしてから新しく設定
    final cookieManager = CookieManager.instance();
    await cookieManager.deleteAllCookies();

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
    debugPrint('[XWebView] init: set ${cookies.length} cookies for ${creds.authToken.substring(0, 8)}...');

    _webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('https://x.com')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent:
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ),
      onLoadStop: (controller, url) {
        debugPrint('[XWebView] onLoadStop: $url');
        _controller = controller;
        if (!_isReady) {
          _isReady = true;
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
            _readyCompleter!.complete();
          }
        }
      },
    );

    await _webView!.run();

    // 最大 15 秒待機
    await _readyCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint('[XWebView] Timeout waiting for page load');
      },
    );
  }

  /// WebView 内の fetch() でツイート投稿
  Future<({bool success, int statusCode, String body})> createTweet(
      XCredentials creds, String text, {String? attachmentUrl}) async {
    final queryId = XQueryIdService.instance.getQueryId('CreateTweet', creds: creds);
    final featuresJson = json.encode(XFeatures.createTweet);

    final variables = <String, dynamic>{
      'tweet_text': text,
      'media': {'media_entities': <dynamic>[], 'possibly_sensitive': false},
      'semantic_annotation_ids': <dynamic>[],
      'disallowed_reply_options': null,
    };

    if (attachmentUrl != null) {
      variables['attachment_url'] = attachmentUrl;
    }

    return _executeMutationWithFeatures(
      creds,
      queryId,
      'CreateTweet',
      variables,
      featuresJson,
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

  /// features 付きミューテーション (CreateTweet 用)
  Future<({bool success, int statusCode, String body})>
      _executeMutationWithFeatures(
    XCredentials creds,
    String queryId,
    String operationName,
    Map<String, dynamic> variables,
    String featuresJson,
  ) async {
    if (_controller == null || _currentAuthToken != creds.authToken) {
      await init(creds);
    }
    if (_controller == null) {
      return (success: false, statusCode: 0, body: 'WebView not ready');
    }

    final ct0 = creds.ct0;

    // リクエストボディ全体を Dart 側で構築して JS に文字列として渡す
    final requestBody = json.encode({
      'variables': variables,
      'features': json.decode(featuresJson),
      'queryId': queryId,
    });

    // callAsyncJavaScript を使って Promise を正しく await する
    final jsBody = '''
      try {
        var url = "https://x.com/i/api/graphql/" + queryId_ + "/$operationName";
        var resp = await fetch(url, {
          method: "POST",
          headers: {
            "Authorization": "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA",
            "Content-Type": "application/json",
            "x-csrf-token": ct0_,
            "x-twitter-auth-type": "OAuth2Session",
            "x-twitter-active-user": "yes",
            "x-twitter-client-language": "en"
          },
          credentials: "include",
          body: body_
        });
        var text = await resp.text();
        return JSON.stringify({status: resp.status, body: text});
      } catch(e) {
        return JSON.stringify({status: 0, body: "JS_ERROR: " + e.toString() + " | " + (e.stack || "")});
      }
    ''';

    try {
      debugPrint('[XWebView] $operationName: queryId=$queryId isReady=$_isReady');
      final jsResult = await _controller!.callAsyncJavaScript(
        functionBody: jsBody,
        arguments: {'queryId_': queryId, 'ct0_': ct0, 'body_': requestBody},
      );

      debugPrint('[XWebView] $operationName: raw=${jsResult?.value}');

      if (jsResult?.value == null) {
        return (success: false, statusCode: 0, body: 'null result from JS');
      }

      final parsed =
          json.decode(jsResult!.value.toString()) as Map<String, dynamic>;
      final statusCode = parsed['status'] as int? ?? 0;
      final body = parsed['body'] as String? ?? '';

      debugPrint('[XWebView] $operationName: status=$statusCode body=${body.length > 300 ? '${body.substring(0, 300)}...' : body}');

      // 成功判定（200でもerrors配列があれば失敗）
      if (statusCode == 200) {
        try {
          final respBody = json.decode(body);
          if (respBody is Map<String, dynamic> &&
              respBody.containsKey('errors')) {
            final errors = respBody['errors'] as List?;
            if (errors != null && errors.isNotEmpty) {
              return (success: false, statusCode: statusCode, body: body);
            }
          }
        } catch (_) {}
      }

      return (success: statusCode == 200, statusCode: statusCode, body: body);
    } catch (e) {
      debugPrint('[XWebView] $operationName dart error: $e');
      return (success: false, statusCode: 0, body: e.toString());
    }
  }

  Future<({bool success, int statusCode, String body})> _executeMutation(
    XCredentials creds,
    String queryId,
    String operationName,
    Map<String, dynamic> variables,
  ) async {
    if (_controller == null || _currentAuthToken != creds.authToken) {
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
              "x-twitter-client-language": "en"
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

      if (result == null) {
        return (success: false, statusCode: 0, body: 'null result');
      }

      final parsed =
          json.decode(result is String ? result : result.toString())
              as Map<String, dynamic>;
      final statusCode = parsed['status'] as int? ?? 0;
      final body = parsed['body'] as String? ?? '';


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
    _readyCompleter = null;
    _currentAuthToken = null;
  }
}
