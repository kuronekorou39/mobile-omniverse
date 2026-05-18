import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../utils/platform_ua.dart';

import '../models/account.dart';
import 'debug_log_service.dart';
import 'image_resize_service.dart';

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

  /// WebView の初回作成（_controller が使えるまで待機）
  Future<void> _ensureWebView() async {
    if (_webView != null && _controller != null) return;

    final controllerCompleter = Completer<void>();
    _readyCompleter = Completer<void>();
    _isReady = false;

    _webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: platformUserAgent,
        domStorageEnabled: true,
        // v1.13.95 で preferredContentMode: MOBILE を入れたが、iPad では
        // iPhone UA × iPad viewport の不整合を X が bot 判定し、noscript
        // エラーページが返ってくるようになった（v1.13.94 以前は問題なく
        // 動いていた）。MOBILE 強制は撤去して、recommended の挙動（iPad は
        // desktop UI、iPhone は mobile UI）に戻す。
      ),
      onConsoleMessage: (controller, msg) {
        // X 側の JS が CSP / Cookie / network 失敗で死んでいる場合の手がかり
        if (msg.messageLevel == ConsoleMessageLevel.ERROR ||
            msg.messageLevel == ConsoleMessageLevel.WARNING) {
          DebugLogService.instance.log(
              'XWebView',
              'console[${msg.messageLevel}]: '
                  '${msg.message.length > 300 ? msg.message.substring(0, 300) : msg.message}');
        }
      },
      onReceivedHttpError: (controller, request, response) {
        if (response.statusCode != null && response.statusCode! >= 400) {
          DebugLogService.instance.log(
              'XWebView',
              'http error ${response.statusCode} for ${request.url}');
        }
      },
      onLoadStop: (controller, url) {
        debugPrint('[XWebView] onLoadStop: $url');
        _controller = controller;
        if (!controllerCompleter.isCompleted) {
          controllerCompleter.complete();
        }
        if (!_isReady && url.toString() != 'about:blank') {
          _isReady = true;
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
            _readyCompleter!.complete();
          }
        }
      },
    );

    await _webView!.run();

    // _controller がセットされるまで待機
    await controllerCompleter.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('[XWebView] Timeout waiting for controller');
      },
    );
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

    // x.com の cookie を可能な限り徹底的にクリアする。
    // deleteCookies(url) だけでは domain/path 違いの cookie が残ることがあり、
    // 特に __cuid（X の anti-bot fingerprint）が前アカウントのまま残ると、
    // X が「auth_token と device fingerprint が矛盾」と判定して JS load を
    // 弾く（ScriptLoadFailure 画面）。 → getCookies で実体を取得して
    // domain/path を指定して個別削除する。
    await _purgeAllXCookies(cookieManager);

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

  /// x.com の全 cookie を、各 cookie の domain/path を見て個別に削除する。
  /// 削除漏れ（特に __cuid など）でアカウント切替時に bot 検知される問題を回避。
  Future<void> _purgeAllXCookies(CookieManager cookieManager) async {
    for (final urlStr in const ['https://x.com', 'https://twitter.com']) {
      try {
        final cookies =
            await cookieManager.getCookies(url: WebUri(urlStr));
        for (final c in cookies) {
          try {
            await cookieManager.deleteCookie(
              url: WebUri(urlStr),
              name: c.name,
              domain: c.domain,
              path: c.path ?? '/',
            );
          } catch (e) {
            debugPrint('[XWebView] deleteCookie failed for ${c.name}: $e');
          }
        }
      } catch (e) {
        debugPrint('[XWebView] getCookies failed for $urlStr: $e');
      }
      // 念のため URL ベースの一括削除も呼ぶ
      try {
        await cookieManager.deleteCookies(url: WebUri(urlStr));
      } catch (_) {}
    }
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
  /// imageFiles が指定された場合は、エディタにテキストを入れた後に
  /// input[type=file] にプログラム的に流し込んでアップロードを開始させる。
  /// 画像は XFile のまま受け取り、_attachImageFiles 内で 1 枚ずつ on-demand に
  /// 読み込む（iPad の WKWebView を OOM kill しないため）。
  Future<({bool success, int statusCode, String body})> createTweet(
      XCredentials creds, String text,
      {String? attachmentUrl,
      String? inReplyToId,
      List<XFile>? imageFiles}) async {
    if (!_isReady || _currentAuthToken != creds.authToken) {
      await init(creds);
    }
    if (_controller == null) {
      return (success: false, statusCode: 0, body: 'WebView not ready');
    }

    final sw = Stopwatch()..start();

    try {
      // 1. 投稿画面をロード（すべて intent URL を使用）
      String composeUrl;
      if (inReplyToId != null) {
        // リプライ
        composeUrl = 'https://x.com/intent/post?in_reply_to=$inReplyToId';
      } else if (attachmentUrl != null) {
        // 引用RT: 元ツイートのURLを添付
        final encodedUrl = Uri.encodeComponent(attachmentUrl);
        composeUrl = 'https://x.com/intent/post?url=$encodedUrl';
      } else {
        // 通常投稿
        composeUrl = 'https://x.com/compose/post';
      }

      debugPrint('[XWebView] createTweet: loading $composeUrl');

      // 診断: 現時点で WKWebView に届いている Cookie の状況。
      // 期待: ct0=..., auth_token=... が含まれること。
      try {
        final cookieDump = await _controller!.evaluateJavascript(
            source: 'document.cookie');
        final cookieStr = cookieDump?.toString() ?? '';
        final masked = cookieStr
            .replaceAllMapped(RegExp(r'(auth_token=)([^;]+)'),
                (m) => '${m.group(1)}<len=${m.group(2)?.length ?? 0}>')
            .replaceAllMapped(RegExp(r'(ct0=)([^;]+)'),
                (m) => '${m.group(1)}<len=${m.group(2)?.length ?? 0}>');
        DebugLogService.instance.log('XWebView',
            'pre-compose document.cookie: ${masked.length > 600 ? masked.substring(0, 600) : masked}');
      } catch (e) {
        DebugLogService.instance.log(
            'XWebView', 'pre-compose cookie dump failed: $e');
      }

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
      // X の DOM は mobile / desktop / iPad で testid が微妙に違うことがある
      // ため、複数のセレクタを OR で試す。タイムアウトも長めに 20 秒。
      const editorSelectors =
          '[data-testid="tweetTextarea_0"],'
          '[data-testid="tweetTextarea_0RichTextInputContainer"],'
          '[role="textbox"][contenteditable="true"],'
          'div[contenteditable="true"][data-text="true"]';
      bool editorReady = await _waitForElement(
        editorSelectors,
        timeoutSeconds: 20,
      );

      // editor が見つからない場合、X の ScriptLoadFailure 画面が出ている
      // ことがあるので "Try again" ボタンを自動で押してリトライする。
      if (!editorReady) {
        final hasScriptFailure = await _controller!.evaluateJavascript(
            source:
                "document.getElementById('ScriptLoadFailure') !== null");
        if (hasScriptFailure == true || hasScriptFailure == 'true') {
          DebugLogService.instance.log('XWebView',
              'createTweet: ScriptLoadFailure detected, clicking Try again');
          try {
            await _controller!.evaluateJavascript(source: '''
              (function() {
                var form = document.querySelector('#ScriptLoadFailure form');
                if (form) { form.submit(); return; }
                var btn = document.querySelector('#ScriptLoadFailure button[type=submit]');
                if (btn) btn.click();
              })();
            ''');
          } catch (e) {
            debugPrint('[XWebView] Try again click failed: $e');
          }
          // page reload を待つ
          await Future.delayed(const Duration(seconds: 4));
          editorReady = await _waitForElement(
            editorSelectors,
            timeoutSeconds: 15,
          );
          if (editorReady) {
            DebugLogService.instance.log('XWebView',
                'createTweet: editor recovered after Try again');
          }
        }
      }

      if (!editorReady) {
        sw.stop();
        const msg = 'Editor not found on compose page';
        // 原因特定用に DOM の概要を debug log に残す（個人情報漏れを避けるため
        // 最初の 1500 文字だけ、アクセス可能なら現在 URL も）
        try {
          final dump = await _controller!.evaluateJavascript(source: '''
            (function() {
              try {
                var url = window.location.href;
                var title = document.title || '';
                var bodyHtml = document.body ? document.body.innerHTML.substring(0, 5000) : '';
                var editables = [];
                document.querySelectorAll('[contenteditable="true"]').forEach(function(el) {
                  editables.push({
                    tag: el.tagName,
                    testid: el.getAttribute('data-testid') || '',
                    role: el.getAttribute('role') || '',
                    aria: el.getAttribute('aria-label') || '',
                  });
                });
                var hasReactRoot = !!document.getElementById('react-root');
                return JSON.stringify({url: url, title: title, hasReactRoot: hasReactRoot, editables: editables, bodyHead: bodyHtml});
              } catch(e) {
                return 'dump_error: ' + e.toString();
              }
            })()
          ''');
          DebugLogService.instance.log('XWebView',
              'createTweet FAIL ($msg) DOM dump: ${dump.toString().substring(0, dump.toString().length.clamp(0, 8000))}');
        } catch (e) {
          DebugLogService.instance.log('XWebView',
              'createTweet FAIL ($msg) dump failed: $e');
        }
        debugPrint('[XWebView] createTweet: $msg');
        DebugLogService.instance.log('XWebView', 'createTweet FAIL: $msg (${sw.elapsedMilliseconds}ms)');
        return (success: false, statusCode: 0, body: msg);
      }

      // 3. テキストを入力
      final textEscaped = json.encode(text);
      await _controller!.evaluateJavascript(source: '''
        (function() {
          var editor = document.querySelector('[data-testid="tweetTextarea_0"]')
                    || document.querySelector('[role="textbox"][contenteditable="true"]');
          if (!editor) return;
          editor.focus();
          document.execCommand('insertText', false, $textEscaped);
          // iOS のソフトキーボードがバックグラウンドで出てくるのを抑制するため
          // すぐ blur する。React は input イベントで内部 state を取り込み
          // 済みなので blur しても入力テキストは保持される。
          try { editor.blur(); } catch(e) {}
          try { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); } catch(e) {}
        })()
      ''');

      await Future.delayed(const Duration(milliseconds: 500));

      // 3.5 画像があれば input[type=file] に流し込んでアップロード完了を待つ
      if (imageFiles != null && imageFiles.isNotEmpty) {
        final attachOk = await _attachImageFiles(imageFiles);
        if (!attachOk) {
          sw.stop();
          const msg = 'Failed to attach images (input not found or upload failed)';
          debugPrint('[XWebView] createTweet: $msg');
          DebugLogService.instance.log('XWebView', 'createTweet FAIL: $msg (${sw.elapsedMilliseconds}ms)');
          return (success: false, statusCode: 0, body: msg);
        }
        final uploaded = await _waitForImageUpload(
            imageFiles.length, timeoutSeconds: 60);
        if (!uploaded) {
          sw.stop();
          const msg = 'Image upload did not complete';
          debugPrint('[XWebView] createTweet: $msg');
          DebugLogService.instance.log('XWebView', 'createTweet FAIL: $msg (${sw.elapsedMilliseconds}ms)');
          return (success: false, statusCode: 0, body: msg);
        }
      }

      // 4. 投稿ボタンをクリック
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
      // 画像/GIF 投稿時は X 側の処理が長引くため、メディアありで 30s、それ以外 15s。
      final posted = await _waitForPostCompletion(
          timeoutSeconds:
              (imageFiles != null && imageFiles.isNotEmpty) ? 30 : 15);
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

  /// XFile を受け取って、1 枚ずつ on-demand に読み込み→リサイズ→base64→注入する。
  /// Android は試行錯誤の末に「DataTransfer に全枚積んで最後に setter call
  /// 1 回」で安定動作している（現状仕様）。iOS は iPad の X 側 React が
  /// 入力直後に input.files をクリアしてしまい複数枚分が拾われないため、
  /// 「1 枚ずつ setter call + change 発火 + delay」に分岐する。
  Future<bool> _attachImageFiles(List<XFile> files) async {
    DebugLogService.instance.log(
        'XWebView', '_attachImageFiles START (${files.length} files)');
    try {
      // 1. 累積 DataTransfer をグローバルに保持
      await _controller!.evaluateJavascript(source: r'''
        try { window.__omniverseDT = new DataTransfer(); } catch(e) {}
      ''');
      DebugLogService.instance.log('XWebView', '_attachImageFiles DT ready');

      // 2. 画像 1 枚ずつ：読み込み → リサイズ → base64 → JS に source 直埋め
      for (var i = 0; i < files.length; i++) {
        DebugLogService.instance.log(
            'XWebView', '_attachImageFiles #$i begin');
        final xfile = files[i];

        Uint8List raw = await xfile.readAsBytes();
        DebugLogService.instance.log('XWebView',
            '_attachImageFiles #$i read ${raw.length}B');

        final isGif = ImageResizeService.isGifBytes(raw);
        Uint8List bytes;
        final String mime;
        final String name;
        if (isGif) {
          bytes = raw;
          mime = 'image/gif';
          name = 'image_$i.gif';
        } else {
          bytes = await ImageResizeService.instance.resizeIfNeeded(
            raw,
            maxBytes: ImageResizeService.xMaxBytes,
          );
          DebugLogService.instance.log('XWebView',
              '_attachImageFiles #$i resized to ${bytes.length}B');
          mime = 'image/jpeg';
          name = 'image_$i.jpg';
        }
        raw = Uint8List(0);

        final b64 = base64Encode(bytes);
        DebugLogService.instance.log('XWebView',
            '_attachImageFiles #$i b64 len=${b64.length}');
        bytes = Uint8List(0);

        final b64Js = json.encode(b64);
        final mimeJs = json.encode(mime);
        final nameJs = json.encode(name);

        // iOS は 1 枚ごとに setter call + change を発火し、X 側の処理を
        // 1.2 秒待ってから次の画像に進む。Android は累積 DT に add するだけで
        // setter call は最後に 1 回（既存挙動）。
        final perImageJs = Platform.isIOS
            ? r'''
              if (!window.__omniverseDT) window.__omniverseDT = new DataTransfer();
              window.__omniverseDT.items.add(file);
              var input = document.querySelector('input[type=file][data-testid="fileInput"]')
                       || document.querySelector('input[data-testid="fileInput"]')
                       || document.querySelector('input[type=file][accept*="image"]')
                       || document.querySelector('input[type=file]');
              if (!input) return JSON.stringify({ ok: false, reason: 'input_not_found' });
              var setter = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'files').set;
              setter.call(input, window.__omniverseDT.files);
              input.dispatchEvent(new Event('change', { bubbles: true }));
              // X 側の React が input.files セット後に editor へ focus を
              // 戻すことがあり、それで iOS のソフトキーボードが裏で点滅する。
              // ここで即 blur しておく。
              try { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); } catch(e) {}
              return JSON.stringify({ ok: true, dt: window.__omniverseDT.files.length, inputLen: input.files.length });
            '''
            : r'''
              if (!window.__omniverseDT) window.__omniverseDT = new DataTransfer();
              window.__omniverseDT.items.add(file);
              return JSON.stringify({ ok: true, count: window.__omniverseDT.files.length });
            ''';

        final result = await _controller!.evaluateJavascript(source: '''
          (function() {
            try {
              var b64 = $b64Js;
              var mime = $mimeJs;
              var name = $nameJs;
              var bin = atob(b64);
              var arr = new Uint8Array(bin.length);
              for (var j = 0; j < bin.length; j++) arr[j] = bin.charCodeAt(j);
              var blob = new Blob([arr], { type: mime });
              var file = new File([blob], name, { type: mime });
              $perImageJs
            } catch (e) {
              return JSON.stringify({ ok: false, message: String(e) });
            }
          })();
        ''');
        DebugLogService.instance.log('XWebView',
            '_attachImageFiles #$i evalJs result: $result');

        Map? parsed;
        try {
          parsed = json.decode(result?.toString() ?? '{}') as Map;
        } catch (_) {}
        if (parsed == null || parsed['ok'] != true) {
          DebugLogService.instance.log('XWebView',
              '_attachImageFiles #$i add failed: $result');
          return false;
        }

        // iOS のみ: 次の change を投げる前に、X 側がこの 1 枚をプレビュー
        // （attachments の img/video）に反映するまで枚数ベースで同期する。
        // 固定 delay だと X の処理タイミングと衝突して、先に投げた 1〜2 枚目が
        // 「もう古い」と捨てられる現象（最後の 2 枚だけ拾われる）が出るため。
        if (Platform.isIOS) {
          final waited = await _waitForAttachmentCount(i + 1,
              timeoutSeconds: 20);
          DebugLogService.instance.log('XWebView',
              '_attachImageFiles #$i previewCount reached: $waited');
        }
      }

      // 3. Android は最後にまとめて setter call。iOS は各ループで実施済み。
      if (!Platform.isIOS) {
        DebugLogService.instance.log(
            'XWebView', '_attachImageFiles commit (android batch)...');
        final finalRaw = await _controller!.evaluateJavascript(source: r'''
          (function() {
            try {
              var input = document.querySelector('input[type=file][data-testid="fileInput"]')
                       || document.querySelector('input[data-testid="fileInput"]')
                       || document.querySelector('input[type=file][accept*="image"]')
                       || document.querySelector('input[type=file]');
              if (!input) return JSON.stringify({ ok: false, reason: 'input_not_found' });
              var setter = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'files').set;
              setter.call(input, window.__omniverseDT.files);
              input.dispatchEvent(new Event('change', { bubbles: true }));
              var count = input.files.length;
              try { delete window.__omniverseDT; } catch(e) {}
              return JSON.stringify({ ok: true, count: count });
            } catch (e) {
              return JSON.stringify({ ok: false, reason: 'js_error', message: String(e) });
            }
          })();
        ''');
        DebugLogService.instance.log('XWebView',
            '_attachImageFiles commit result: $finalRaw');
        Map? parsed;
        try {
          parsed = json.decode(finalRaw?.toString() ?? '{}') as Map;
        } catch (_) {}
        return parsed != null && parsed['ok'] == true;
      }

      // iOS: 後片付けだけ
      await _controller!.evaluateJavascript(source: r'''
        try { delete window.__omniverseDT; } catch(e) {}
      ''');
      DebugLogService.instance.log('XWebView',
          '_attachImageFiles DONE (ios per-image)');
      return true;
    } catch (e, st) {
      debugPrint('[XWebView] _attachImageFiles error: $e\n$st');
      DebugLogService.instance.log('XWebView',
          '_attachImageFiles ERROR: $e');
      return false;
    }
  }

  /// プレビュー DOM の枚数が `expected` 以上 + 進行中の progressbar が
  /// なくなる（=その 1 枚の upload 完了）まで待つ。
  /// 単にプレビューが出ただけでは upload 中の可能性があり、その間に次の
  /// change を投げると X 側の処理がぶつかって枚数が欠けるため、ここで
  /// 完了を確認する。
  Future<bool> _waitForAttachmentCount(int expected,
      {int timeoutSeconds = 30}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (DateTime.now().isBefore(deadline)) {
      final r = await _controller!.evaluateJavascript(source: '''
        (function() {
          var nodes = document.querySelectorAll(
            '[data-testid="attachments"] img,'
            + '[data-testid="attachments"] video,'
            + '[data-testid="tweetPhoto"],'
            + '[data-testid="gifPlayer"]'
          );
          var progressBars = document.querySelectorAll('[role="progressbar"]');
          return JSON.stringify({ count: nodes.length, progress: progressBars.length });
        })()
      ''');
      Map? parsed;
      try {
        parsed = json.decode(r?.toString() ?? '{}') as Map;
      } catch (_) {}
      final count = (parsed?['count'] as int?) ?? 0;
      final progress = (parsed?['progress'] as int?) ?? 0;
      if (count >= expected && progress == 0) return true;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  /// 画像アップロード完了を検知。プレビュー DOM が指定枚数ぶん表示されるまで待つ。
  /// 単にプレビューが出ただけでは upload 中のことがあり、その状態で投稿ボタンを
  /// 押すと X が「現時点で upload 完了済みのものだけ」で tweet を作って投稿
  /// する事象があった（4 枚指定なのに 2-3 枚で投稿される現象の原因）。
  /// 完了の確実な目印として、ページ内に role="progressbar" が 1 つも存在しない
  /// 状態が連続で 1 秒以上維持されることを確認する。
  Future<bool> _waitForImageUpload(int expected,
      {int timeoutSeconds = 90}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (DateTime.now().isBefore(deadline)) {
      final stable = await _checkUploadStableOnce(expected);
      if (stable) {
        // 1 秒待ってもう一度安定確認（フリッカー対策）
        await Future.delayed(const Duration(seconds: 1));
        if (await _checkUploadStableOnce(expected)) return true;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<bool> _checkUploadStableOnce(int expected) async {
    final r = await _controller!.evaluateJavascript(source: '''
      (function() {
        var nodes = document.querySelectorAll(
          '[data-testid="attachments"] img,'
          + '[data-testid="attachments"] video,'
          + '[data-testid="tweetPhoto"],'
          + '[data-testid="gifPlayer"]'
        );
        var progressBars = document.querySelectorAll('[role="progressbar"]');
        var btnEnabled = document.querySelector('[data-testid="tweetButton"]:not([disabled])') !== null
          || document.querySelector('[data-testid="tweetButtonInline"]:not([disabled])') !== null;
        return JSON.stringify({
          count: nodes.length,
          progress: progressBars.length,
          btn: btnEnabled
        });
      })()
    ''');
    Map? parsed;
    try {
      parsed = json.decode(r?.toString() ?? '{}') as Map;
    } catch (_) {}
    final count = (parsed?['count'] as int?) ?? 0;
    final progress = (parsed?['progress'] as int?) ?? 0;
    final btn = (parsed?['btn'] as bool?) ?? false;
    return count >= expected && progress == 0 && btn;
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

  /// 投稿完了を検知（投稿画面が閉じた or エディタが消えた or URL変化 or
  /// 投稿ボタンが DOM から消えた）。
  /// タイムアウトしても、エディタに入力テキストが残っていなければ「投稿は通った」
  /// とみなす。GIF→MP4 変換などで X 側の後処理が長引いて検知サインを取り逃しても、
  /// 実投稿に成功していれば誤って失敗にしないため。
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

      // 投稿ボタンが DOM から消えた（モーダルが投稿後にクローズ中）
      final buttonGone = await _controller!.evaluateJavascript(
        source: '''
          document.querySelector('[data-testid="tweetButton"]') === null
          && document.querySelector('[data-testid="tweetButtonInline"]') === null
        ''',
      );
      if (buttonGone == true || buttonGone == 'true') return true;
    }

    // タイムアウト時の最終確認: エディタが空なら投稿は通っているとみなす
    final editorEmpty = await _controller!.evaluateJavascript(
      source: '''
        (function() {
          var editor = document.querySelector('[data-testid="tweetTextarea_0"]')
                    || document.querySelector('[role="textbox"][contenteditable="true"]');
          if (!editor) return true;
          var text = editor.textContent || editor.innerText || '';
          return text.trim().length === 0;
        })()
      ''',
    );
    if (editorEmpty == true || editorEmpty == 'true') {
      DebugLogService.instance.log('XWebView',
          '_waitForPostCompletion: timeout but editor is empty -> treat as success');
      return true;
    }
    return false;
  }

  // ─── リツイート/アンリツイート (DOM操作方式) ───

  /// ツイートページを開いてRTボタンをDOM操作でクリック
  Future<({bool success, int statusCode, String body})> retweet(
      XCredentials creds, String tweetId) async {
    return _executeRetweetAction(creds, tweetId, undo: false);
  }

  /// ツイートページを開いてアンRTをDOM操作で実行
  Future<({bool success, int statusCode, String body})> unretweet(
      XCredentials creds, String tweetId) async {
    return _executeRetweetAction(creds, tweetId, undo: true);
  }

  Future<({bool success, int statusCode, String body})> _executeRetweetAction(
      XCredentials creds, String tweetId, {required bool undo}) async {
    if (!_isReady || _currentAuthToken != creds.authToken) {
      await init(creds);
    }
    if (_controller == null) {
      return (success: false, statusCode: 0, body: 'WebView not ready');
    }

    final sw = Stopwatch()..start();
    final operation = undo ? 'DeleteRetweet_DOM' : 'CreateRetweet_DOM';

    try {
      // 1. ツイートページを開く
      final tweetUrl = 'https://x.com/i/status/$tweetId';
      debugPrint('[XWebView] $operation: loading $tweetUrl');

      _isReady = false;
      _readyCompleter = Completer<void>();
      await _controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri(tweetUrl)),
      );

      await _readyCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _isReady = true;
        },
      );

      // 2. RTボタンを探してクリック
      final rtReady = await _waitForElement(
        '[data-testid="retweet"], [data-testid="unretweet"]',
        timeoutSeconds: 10,
      );
      if (!rtReady) {
        sw.stop();
        const msg = 'Retweet button not found';
        DebugLogService.instance.log('XWebView', '$operation FAIL: $msg');
        return (success: false, statusCode: 0, body: msg);
      }

      await _controller!.evaluateJavascript(source: '''
        (function() {
          var btn = document.querySelector('[data-testid="retweet"]')
                 || document.querySelector('[data-testid="unretweet"]');
          if (btn) btn.click();
        })()
      ''');

      await Future.delayed(const Duration(milliseconds: 500));

      // 3. メニューから「リポスト」または「リポストを取り消す」をクリック
      final menuSelector = undo
          ? '[data-testid="unretweetConfirm"]'
          : '[data-testid="retweetConfirm"]';

      final menuReady = await _waitForElement(menuSelector, timeoutSeconds: 5);
      if (!menuReady) {
        // メニューが出ない場合（直接RT/アンRTされた可能性）
        sw.stop();
        await _saveCookies(creds.authToken);
        debugPrint('[XWebView] $operation: no confirm menu, assuming direct action');
        DebugLogService.instance.log('XWebView', '$operation: completed (no confirm menu) ${sw.elapsedMilliseconds}ms');
        return (success: true, statusCode: 200, body: 'Direct action (no menu)');
      }

      await _controller!.evaluateJavascript(source: '''
        (function() {
          var item = document.querySelector('$menuSelector');
          if (item) item.click();
        })()
      ''');

      await Future.delayed(const Duration(milliseconds: 500));
      sw.stop();
      await _saveCookies(creds.authToken);

      debugPrint('[XWebView] $operation: SUCCESS (${sw.elapsedMilliseconds}ms)');
      DebugLogService.instance.log('XWebView', '$operation: completed ${sw.elapsedMilliseconds}ms');
      return (success: true, statusCode: 200, body: 'DOM action succeeded');
    } catch (e) {
      sw.stop();
      debugPrint('[XWebView] $operation error: $e');
      DebugLogService.instance.log('XWebView', '$operation ERROR: $e');
      return (success: false, statusCode: 0, body: e.toString());
    }
  }

  void dispose() {
    // Cookie保存は非同期だがdisposeはsyncなのでベストエフォート
    if (_currentAuthToken != null) {
      _saveCookies(_currentAuthToken!).ignore();
    }
    _webView?.dispose();
    _webView = null;
    _controller = null;
    _isReady = false;
    _readyCompleter = null;
    _currentAuthToken = null;
  }
}
