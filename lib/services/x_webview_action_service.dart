import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/account.dart';
import 'debug_log_service.dart';

/// X の投稿を、WebView 上で公式の投稿画面 (x.com/compose/post) を
/// DOM 操作して実行するサービス。
/// X 自身の JS が x-client-transaction-id 等を生成するため、bot 検知を回避できる。
///
/// WebView インスタンスは使い回し、アカウント切替時は cookie 入替+リロードのみ。
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

  /// WebView の初回作成
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
        domStorageEnabled: true,
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

  /// アカウントの cookie をセットして x.com をロード
  Future<void> init(XCredentials creds) async {
    if (_isReady && _currentAuthToken == creds.authToken) return;

    await _ensureWebView();

    final cookieManager = CookieManager.instance();

    // 現アカウントの cookie を保存
    if (_currentAuthToken != null && _isReady) {
      await _saveCookies(_currentAuthToken!);
    }

    _currentAuthToken = creds.authToken;

    // x.com の cookie をクリア
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

    // x.com をロード
    _isReady = false;
    _readyCompleter = Completer<void>();
    await _controller!.loadUrl(
      urlRequest: URLRequest(url: WebUri('https://x.com')),
    );

    bool timedOut = false;
    await _readyCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        timedOut = true;
        debugPrint('[XWebView] Timeout waiting for page load');
        _isReady = true;
      },
    );

    await Future.delayed(const Duration(seconds: 2));
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

  // ─── 投稿 (DOM操作方式) ───

  /// x.com/compose/post をDOM操作して投稿する
  /// 公式のJSが x-client-transaction-id 等を付与するため bot 検知を回避できる
  Future<({bool success, int statusCode, String body})> createTweet(
      XCredentials creds, String text,
      {String? attachmentUrl, String? inReplyToId}) async {
    if (!_isReady || _currentAuthToken != creds.authToken) {
      await init(creds);
    }
    if (_controller == null) {
      return (success: false, statusCode: 0, body: 'WebView not ready');
    }

    final sw = Stopwatch()..start();

    try {
      // 1. 投稿画面をロード
      String composeUrl = 'https://x.com/compose/post';
      if (inReplyToId != null) {
        composeUrl += '?reply_to=$inReplyToId';
      } else if (attachmentUrl != null) {
        composeUrl += '?quote_tweet_id=${_extractTweetId(attachmentUrl)}';
      }

      debugPrint('[XWebView] createTweet: loading $composeUrl');

      _isReady = false;
      _readyCompleter = Completer<void>();
      await _controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri(composeUrl)),
      );

      await _readyCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _isReady = true;
          debugPrint('[XWebView] Timeout waiting for compose page');
        },
      );

      // 2. エディタが表示されるまで待つ
      final editorReady = await _waitForElement(
        '[data-testid="tweetTextarea_0"], [role="textbox"][contenteditable="true"]',
        timeoutSeconds: 10,
      );
      if (!editorReady) {
        sw.stop();
        const msg = 'Editor not found on compose page';
        debugPrint('[XWebView] createTweet: $msg');
        DebugLogService.instance.log('XWebView', 'createTweet FAIL: $msg (${sw.elapsedMilliseconds}ms)');
        return (success: false, statusCode: 0, body: msg);
      }

      // 3. テキストを入力（contenteditable divに対してInputEventを発火）
      final textEscaped = json.encode(text); // JSの文字列リテラル用にエスケープ
      await _controller!.evaluateJavascript(source: '''
        (function() {
          var editor = document.querySelector('[data-testid="tweetTextarea_0"]')
                    || document.querySelector('[role="textbox"][contenteditable="true"]');
          if (!editor) return;
          editor.focus();
          // テキストを挿入
          document.execCommand('insertText', false, $textEscaped);
        })()
      ''');

      // 入力が反映されるまで少し待つ
      await Future.delayed(const Duration(milliseconds: 500));

      // 4. 投稿ボタンを探してクリック
      final buttonReady = await _waitForElement(
        '[data-testid="tweetButton"]:not([disabled]), [data-testid="tweetButtonInline"]:not([disabled])',
        timeoutSeconds: 5,
      );
      if (!buttonReady) {
        sw.stop();
        const msg = 'Tweet button not found or disabled';
        debugPrint('[XWebView] createTweet: $msg');
        DebugLogService.instance.log('XWebView', 'createTweet FAIL: $msg (${sw.elapsedMilliseconds}ms)');
        return (success: false, statusCode: 0, body: msg);
      }

      await _controller!.evaluateJavascript(source: '''
        (function() {
          var btn = document.querySelector('[data-testid="tweetButton"]:not([disabled])')
                 || document.querySelector('[data-testid="tweetButtonInline"]:not([disabled])');
          if (btn) btn.click();
        })()
      ''');

      // 5. 投稿完了を待つ（投稿画面が閉じる or エディタが空になる）
      final posted = await _waitForPostCompletion(timeoutSeconds: 15);
      sw.stop();

      await _saveCookies(creds.authToken);

      final duration = sw.elapsedMilliseconds;
      if (posted) {
        debugPrint('[XWebView] createTweet: SUCCESS (${duration}ms)');
        DebugLogService.instance.logWebView(
          tag: 'XWebView',
          operation: 'CreateTweet_DOM',
          queryId: '',
          ct0: '',
          requestBody: text,
          statusCode: 200,
          responseBody: 'DOM post succeeded',
          duration: sw.elapsed,
          extra: {'authToken': creds.authToken.substring(0, 8)},
        );
        return (success: true, statusCode: 200, body: 'Posted via DOM');
      } else {
        debugPrint('[XWebView] createTweet: FAIL - completion not detected (${duration}ms)');
        DebugLogService.instance.logWebView(
          tag: 'XWebView',
          operation: 'CreateTweet_DOM',
          queryId: '',
          ct0: '',
          requestBody: text,
          statusCode: 0,
          responseBody: 'Post completion not detected',
          duration: sw.elapsed,
          extra: {'authToken': creds.authToken.substring(0, 8)},
        );
        return (success: false, statusCode: 0, body: 'Post completion not detected');
      }
    } catch (e) {
      sw.stop();
      debugPrint('[XWebView] createTweet error: $e');
      DebugLogService.instance.log('XWebView', 'createTweet ERROR: $e (${sw.elapsedMilliseconds}ms)');
      return (success: false, statusCode: 0, body: e.toString());
    }
  }

  /// permalink URL からツイートIDを抽出
  String _extractTweetId(String url) {
    final match = RegExp(r'/status/(\d+)').firstMatch(url);
    return match?.group(1) ?? url;
  }

  /// 指定セレクタの要素が出現するまでポーリング
  Future<bool> _waitForElement(String selector, {int timeoutSeconds = 10}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (DateTime.now().isBefore(deadline)) {
      final found = await _controller!.evaluateJavascript(
        source: 'document.querySelector(\'${selector.replaceAll("'", "\\'")}\') !== null',
      );
      if (found == true || found == 'true') return true;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  /// 投稿完了を検知（投稿画面が閉じた or エディタが消えた or URL変化）
  Future<bool> _waitForPostCompletion({int timeoutSeconds = 15}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));

    // 投稿直後のURLを記録
    final initialUrl = (await _controller!.getUrl())?.toString() ?? '';

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 500));

      // URL が compose/post から変わった → 投稿完了
      final currentUrl = (await _controller!.getUrl())?.toString() ?? '';
      if (currentUrl != initialUrl && !currentUrl.contains('/compose/')) {
        return true;
      }

      // 投稿成功のトースト/スナックバーが表示された
      final hasToast = await _controller!.evaluateJavascript(
        source: '''
          document.querySelector('[data-testid="toast"]') !== null
          || document.querySelector('[role="alert"]') !== null
        ''',
      );
      if (hasToast == true || hasToast == 'true') return true;

      // エディタが消えた（モーダルが閉じた）
      final editorGone = await _controller!.evaluateJavascript(
        source: '''
          document.querySelector('[data-testid="tweetTextarea_0"]') === null
          && document.querySelector('[role="textbox"][contenteditable="true"]') === null
        ''',
      );
      if (editorGone == true || editorGone == 'true') return true;
    }
    return false;
  }

  // ─── リツイート/アンリツイート (fetch方式を維持) ───

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
