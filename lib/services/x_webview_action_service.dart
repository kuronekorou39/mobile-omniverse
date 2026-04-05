import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/account.dart';
import 'debug_log_service.dart';
import 'x_features.dart';
import 'x_query_id_service.dart';

/// X の CDN が x-client-transaction-id を暗号学的に検証するエンドポイント
/// (CreateTweet, CreateRetweet, DeleteRetweet 等) を、隠し WebView 経由で実行するサービス。
/// WebView はブラウザとして正規のヘッダーを自動生成するため、検証を通過できる。
///
/// WebView インスタンスは使い回し、アカウント切替時はcookie入替+リロードのみ。
/// localStorage/sessionStorage/ブラウザ指紋を維持し、正規ブラウザと同じ状態を保つ。
class XWebViewActionService {
  XWebViewActionService._();
  static final instance = XWebViewActionService._();

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  bool _isReady = false;
  Completer<void>? _readyCompleter;
  String? _currentAuthToken;

  /// アカウントごとの全 cookie を保持 (authToken → cookie list)
  final Map<String, List<Cookie>> _accountCookies = {};

  /// WebView の初回作成（まだ存在しない場合のみ）
  Future<void> _ensureWebView() async {
    if (_webView != null) return;

    _readyCompleter = Completer<void>();
    _isReady = false;

    _webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent:
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ),
      onLoadStop: (controller, url) {
        debugPrint('[XWebView] onLoadStop: $url');
        _controller = controller;
        if (!_isReady && url.toString() != 'about:blank') {
          _isReady = true;
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
            _readyCompleter!.complete();
          }
        }
      },
    );

    await _webView!.run();
  }

  /// アカウントの cookie をセットして x.com をロード（または既にロード済みならスキップ）
  Future<void> init(XCredentials creds) async {
    // 同一アカウントで初期化済みならスキップ
    if (_isReady && _currentAuthToken == creds.authToken) return;

    // WebView がなければ作成（初回のみ）
    await _ensureWebView();

    final cookieManager = CookieManager.instance();

    // 現アカウントの cookie を保存
    if (_currentAuthToken != null && _isReady) {
      await _saveCookies(_currentAuthToken!);
    }

    _currentAuthToken = creds.authToken;

    // x.com の cookie をクリア（全体ではなくドメイン限定）
    await cookieManager.deleteCookies(url: WebUri('https://x.com'));

    // アカウントの cookie を復元
    final saved = _accountCookies[creds.authToken];
    if (saved != null && saved.isNotEmpty) {
      debugPrint('[XWebView] init: restoring ${saved.length} saved cookies for ${creds.authToken.substring(0, 8)}...');
      for (final cookie in saved) {
        await cookieManager.setCookie(
          url: WebUri('https://x.com'),
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain ?? '.x.com',
          path: cookie.path ?? '/',
          isSecure: cookie.isSecure,
          isHttpOnly: cookie.isHttpOnly,
          expiresDate: cookie.expiresDate,
        );
      }
    } else {
      debugPrint('[XWebView] init: setting cookies from credentials for ${creds.authToken.substring(0, 8)}...');
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
    }

    // x.com をロード（WebView は維持したまま）
    _isReady = false;
    _readyCompleter = Completer<void>();
    await _controller!.loadUrl(
      urlRequest: URLRequest(url: WebUri('https://x.com')),
    );

    // 最大 15 秒待機
    bool timedOut = false;
    await _readyCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        timedOut = true;
        debugPrint('[XWebView] Timeout waiting for page load');
        _isReady = true; // タイムアウトでも続行
      },
    );

    // ページロード後、X の JS が cookie やトークンを更新する時間を待つ
    await Future.delayed(const Duration(seconds: 2));

    // 更新された cookie を保存
    await _saveCookies(creds.authToken);

    DebugLogService.instance.log('XWebView',
        'init complete: authToken=${creds.authToken.substring(0, 8)}... '
        'isReady=$_isReady timedOut=$timedOut '
        'savedCookies=${_accountCookies[creds.authToken]?.length ?? 0}');
  }

  /// 現在の WebView の全 cookie を保存
  Future<void> _saveCookies(String authToken) async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri('https://x.com'),
      );
      _accountCookies[authToken] = cookies;
      debugPrint('[XWebView] saved ${cookies.length} cookies for ${authToken.substring(0, 8)}...');
    } catch (e) {
      debugPrint('[XWebView] Failed to save cookies: $e');
    }
  }

  /// WebView の CookieManager から実際の ct0 を取得
  Future<String> _getWebViewCt0(XCredentials creds) async {
    try {
      final cookie = await CookieManager.instance().getCookie(
        url: WebUri('https://x.com'),
        name: 'ct0',
      );
      if (cookie != null && cookie.value.isNotEmpty) {
        return cookie.value;
      }
    } catch (e) {
      debugPrint('[XWebView] Failed to read ct0 cookie: $e');
    }
    return creds.ct0;
  }

  /// WebView 内の fetch() でツイート投稿
  Future<({bool success, int statusCode, String body})> createTweet(
      XCredentials creds, String text,
      {String? attachmentUrl, String? inReplyToId}) async {
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
    if (inReplyToId != null) {
      variables['reply'] = {
        'in_reply_to_tweet_id': inReplyToId,
        'exclude_reply_user_ids': <dynamic>[],
      };
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
    if (!_isReady || _currentAuthToken != creds.authToken) {
      await init(creds);
    }
    if (_controller == null) {
      return (success: false, statusCode: 0, body: 'WebView not ready');
    }

    final ct0 = await _getWebViewCt0(creds);

    final requestBody = json.encode({
      'variables': variables,
      'features': json.decode(featuresJson),
      'queryId': queryId,
    });

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

    final sw = Stopwatch()..start();
    try {
      debugPrint('[XWebView] $operationName: queryId=$queryId isReady=$_isReady');
      final jsResult = await _controller!.callAsyncJavaScript(
        functionBody: jsBody,
        arguments: {'queryId_': queryId, 'ct0_': ct0, 'body_': requestBody},
      );
      sw.stop();

      final rawValue = jsResult?.value?.toString();
      debugPrint('[XWebView] $operationName: raw=$rawValue');

      // ミューテーション後に cookie を保存
      await _saveCookies(creds.authToken);

      if (jsResult?.value == null) {
        DebugLogService.instance.logWebView(
          tag: 'XWebView',
          operation: operationName,
          queryId: queryId,
          ct0: ct0,
          requestBody: requestBody,
          jsRawResult: 'null',
          error: 'null result from JS',
          duration: sw.elapsed,
          extra: {'isReady': _isReady, 'authToken': creds.authToken.substring(0, 8)},
        );
        return (success: false, statusCode: 0, body: 'null result from JS');
      }

      final parsed =
          json.decode(jsResult!.value.toString()) as Map<String, dynamic>;
      final statusCode = parsed['status'] as int? ?? 0;
      final body = parsed['body'] as String? ?? '';

      debugPrint('[XWebView] $operationName: status=$statusCode body=${body.length > 300 ? '${body.substring(0, 300)}...' : body}');

      bool success = statusCode == 200;
      if (statusCode == 200) {
        try {
          final respBody = json.decode(body);
          if (respBody is Map<String, dynamic> &&
              respBody.containsKey('errors')) {
            final errors = respBody['errors'] as List?;
            if (errors != null && errors.isNotEmpty) {
              success = false;
            }
          }
        } catch (_) {}
      }

      DebugLogService.instance.logWebView(
        tag: 'XWebView',
        operation: operationName,
        queryId: queryId,
        ct0: ct0,
        requestBody: requestBody,
        jsRawResult: rawValue,
        statusCode: statusCode,
        responseBody: body,
        duration: sw.elapsed,
        extra: {'isReady': _isReady, 'success': success, 'authToken': creds.authToken.substring(0, 8)},
      );

      // 226 (automated detection) → saved cookie を破棄して次回の手動投稿でフレッシュinitさせる
      if (!success && body.contains('"code":226')) {
        debugPrint('[XWebView] 226 detected, clearing saved cookies for next attempt');
        _accountCookies.remove(creds.authToken);
        _currentAuthToken = null;
        _isReady = false;
      }

      return (success: success, statusCode: statusCode, body: body);
    } catch (e) {
      sw.stop();
      debugPrint('[XWebView] $operationName dart error: $e');
      DebugLogService.instance.logWebView(
        tag: 'XWebView',
        operation: operationName,
        queryId: queryId,
        ct0: ct0,
        requestBody: requestBody,
        error: e.toString(),
        duration: sw.elapsed,
        extra: {'isReady': _isReady, 'authToken': creds.authToken.substring(0, 8)},
      );
      return (success: false, statusCode: 0, body: e.toString());
    }
  }

  Future<({bool success, int statusCode, String body})> _executeMutation(
    XCredentials creds,
    String queryId,
    String operationName,
    Map<String, dynamic> variables,
  ) async {
    if (!_isReady || _currentAuthToken != creds.authToken) {
      await init(creds);
    }
    if (_controller == null) {
      return (success: false, statusCode: 0, body: 'WebView not ready');
    }

    final variablesJson = json.encode(variables);
    final ct0 = await _getWebViewCt0(creds);

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

    final sw = Stopwatch()..start();
    try {
      final result = await _controller!.evaluateJavascript(source: js);
      sw.stop();

      // ミューテーション後に cookie を保存
      await _saveCookies(creds.authToken);

      if (result == null) {
        DebugLogService.instance.logWebView(
          tag: 'XWebView',
          operation: operationName,
          queryId: queryId,
          ct0: ct0,
          requestBody: variablesJson,
          jsRawResult: 'null',
          error: 'null result',
          duration: sw.elapsed,
        );
        return (success: false, statusCode: 0, body: 'null result');
      }

      final parsed =
          json.decode(result is String ? result : result.toString())
              as Map<String, dynamic>;
      final statusCode = parsed['status'] as int? ?? 0;
      final body = parsed['body'] as String? ?? '';

      DebugLogService.instance.logWebView(
        tag: 'XWebView',
        operation: operationName,
        queryId: queryId,
        ct0: ct0,
        requestBody: variablesJson,
        jsRawResult: result.toString(),
        statusCode: statusCode,
        responseBody: body,
        duration: sw.elapsed,
      );

      return (success: statusCode == 200, statusCode: statusCode, body: body);
    } catch (e) {
      sw.stop();
      debugPrint('[XWebView] $operationName error: $e');
      DebugLogService.instance.logWebView(
        tag: 'XWebView',
        operation: operationName,
        queryId: queryId,
        ct0: ct0,
        requestBody: variablesJson,
        error: e.toString(),
        duration: sw.elapsed,
      );
      return (success: false, statusCode: 0, body: e.toString());
    }
  }

  void dispose() {
    if (_currentAuthToken != null) {
      _saveCookies(_currentAuthToken!);
    }
    _webView?.dispose();
    _webView = null;
    _controller = null;
    _isReady = false;
    _readyCompleter = null;
    _currentAuthToken = null;
  }
}
