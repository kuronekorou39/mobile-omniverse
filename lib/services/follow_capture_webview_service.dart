import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/account.dart';
import '../models/x_rate_limit.dart';
import '../utils/platform_ua.dart';
import 'debug_log_service.dart';
import 'follow_capture_engine.dart';
import 'follow_list_parser.dart';

/// フォロー/フォロワー一覧を「X 自身のページの中から」取得するサービス。
///
/// X は Followers / Following で `x-client-transaction-id` を検証しており、
/// 実測の結果:
///   - ランダムな txId → 404
///   - 捕獲した本物の txId をページ内 fetch で使う → 200
///   - 捕獲した本物の txId を Dart の http で使う → 404
/// つまり **ページコンテキストから送るしかない**。
/// (Follow-Capture-Tool が proxyFetch でキャプチャタブに fetch を代行させて
///  いるのと同じ理由)
///
/// そこで常駐 HeadlessWebView で対象の一覧ページを開き、X 自身が出した
/// リクエストを捕獲して、以降は cursor だけ差し替えてページ内で再送する。
/// アカウント切替は cookie 入替 + 再ロードで行う
/// (XWebViewActionService と同じ方式)。
class FollowCaptureWebViewService {
  FollowCaptureWebViewService._();
  static final instance = FollowCaptureWebViewService._();

  /// 捕獲を諦めるまでの総時間。
  ///
  /// この中で何度か読み込み直す ([_reloadAfter] 参照)。
  static const _captureTimeout = Duration(seconds: 75);

  /// 1 本も通信が来ないまま この時間が過ぎたら、ページを読み込み直す。
  ///
  /// 直前に同じユーザーの別の一覧を開いていると、X がキャッシュから
  /// 描画してリクエストを 1 本も出さないことがある (実測: フォロー取得の
  /// 直後にフォロワーを開くと seen=[] のまま 75 秒経過)。この状態は
  /// いくら待っても変わらないので、待つのではなく開き直す。
  static const _reloadAfter = Duration(seconds: 20);

  /// 読み込み直す上限。これを超えたら諦める
  static const _maxReloads = 3;
  static const _fetchTimeout = Duration(seconds: 45);

  /// 捕獲後、ページの初期化が落ち着くまでの待ち
  static const _settleDelay = Duration(seconds: 6);

  /// txId のクールダウンは **endpoint ごとに独立**している (実測済み)。
  /// 同じトークンでも Followers と Following で別々にカウントされるため、
  /// 1 セットのトークンを両方で共用できる。
  ///
  /// 値は Follow-Capture-Tool の実績に合わせる:
  ///   Followers … 60秒 (枠が 50/15分 と厳しく、実効 20秒/ページ)
  ///   Following … 2秒  (枠が 500/15分 ＝ 1.8秒/回 なので事実上こちらが上限)
  static const txCooldownFollowers = Duration(seconds: 60);
  static const txCooldownFollowing = Duration(seconds: 2);

  static Duration txCooldownOf(FollowListKind kind) =>
      kind == FollowListKind.followers
          ? txCooldownFollowers
          : txCooldownFollowing;

  /// 保持する txId の数。Followers の実効間隔 = 60秒 / 個数
  static const txPoolSize = 3;

  /// リロードで txId を集めるときの 1 回あたりの待ち上限
  static const _harvestTimeout = Duration(seconds: 25);

  /// 採取済みの txId。endpoint をまたいで共用できる
  final Set<String> _txIds = {};

  /// 「txId × endpoint」ごとの最終使用時刻。キーは '<kind>|<txId>'
  final Map<String, DateTime> _txUsedAt = {};

  /// いま捕獲中の種別 (採取した txId をどちらで消費したことにするか)
  FollowListKind? _capturingKind;

  static String _txKey(FollowListKind kind, String tx) => '${kind.name}|$tx';

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  String? _currentAuthToken;

  /// アカウントごとの全 cookie を保持 (authToken → cookie list)
  final Map<String, List<Cookie>> _accountCookies = {};

  /// 捕獲中の対象を表すキー (authToken | handle | kind)
  String? _capturedKey;
  String? _capturedUrl;
  Map<String, String>? _capturedHeaders;

  /// 捕獲時のレスポンスを 1 回だけ返すための控え。
  /// これを使わないと 1 ページ目を無駄に 2 回叩くことになる。
  FollowListPage? _pendingInitialPage;

  Completer<void>? _captureCompleter;
  Completer<String>? _fetchCompleter;

  bool get hasCapture => _capturedUrl != null && _capturedHeaders != null;

  static String _key(String authToken, String handle, FollowListKind kind) =>
      '$authToken|${handle.toLowerCase()}|${kind.name}';

  // ─── WebView の生成 ───

  /// ホスト側の InAppWebView に注入するインターセプタ
  static const interceptorScript = _interceptorScript;

  static const _interceptorScript = r'''
(function(){
  if (window.__fcw_installed) return;
  window.__fcw_installed = true;
  window.__fcw_replaying = false;

  // 末尾のオペレーション名が完全一致するものだけを対象にする。
  // 部分一致だと /FollowersYouKnow や /FollowingTimeline を誤って掴む。
  var TARGET = /\/(Followers|Following)(\?|$)/;

  // ★ cursor を含むリクエストは捕獲しない。
  // ページが勝手に次ページを読むことがあり、それを雛形にすると
  // 1 ページ目が丸ごと抜け落ちる。
  function hasCursor(url){
    var m = /[?&]variables=([^&]*)/.exec(url);
    if (!m) return false;
    try { return JSON.parse(decodeURIComponent(m[1])).cursor != null; }
    catch(e) { return false; }
  }

  function isTarget(url){
    return typeof url === 'string' && TARGET.test(url) && !hasCursor(url);
  }

  function report(payload){
    try {
      window.flutter_inappwebview.callHandler('onFollowCaptured', JSON.stringify(payload));
    } catch(e) {}
  }

  // 診断: 捕獲できないとき「X が何を投げていたか」が分からないと
  // 手が出せない。GraphQL のオペレーション名と status だけを別口で報告する。
  //
  // 橋 (WebView↔ネイティブ) の往復はただではない。全リクエストで呼ぶと
  // 本来の捕獲通知と競合しかねないので、GraphQL に限り、
  // 同じ名前は 1 回しか送らない。
  window.__fcw_seen = {};
  function seen(url, status){
    try {
      var m = /\/i\/api\/graphql\/[^\/]+\/([A-Za-z0-9_]+)/.exec(String(url));
      if (!m) return;
      var key = m[1] + ':' + status + (hasCursor(String(url)) ? ':cursor' : '');
      if (window.__fcw_seen[key]) return;
      window.__fcw_seen[key] = 1;
      window.flutter_inappwebview.callHandler('onFollowSeen', key);
    } catch(e) {}
  }

  var originalFetch = window.fetch;
  window.fetch = function(){
    var args = arguments;
    var p = originalFetch.apply(this, args);
    try {
      if (window.__fcw_replaying) return p;
      var req = args[0];
      var url = (req && req.url) ? req.url : String(req);
      if (String(url).indexOf('/i/api/graphql/') >= 0) {
        p.then(function(r){ seen(url, r.status); })
         .catch(function(){ seen(url, 'ERR'); });
      }
      if (!isTarget(url)) return p;

      var headers = {};
      if (req && req.headers && req.headers.forEach) {
        req.headers.forEach(function(v,k){ headers[k]=v; });
      }
      var init = args[1];
      if (init && init.headers) {
        if (init.headers.forEach) init.headers.forEach(function(v,k){ headers[k]=v; });
        else for (var k in init.headers) headers[k]=init.headers[k];
      }
      p.then(function(r){ return r.clone(); }).then(function(c){
        if (c.status !== 200) return;
        return c.text().then(function(body){
          report({url:url, headers:headers, body:body});
        });
      }).catch(function(){});
    } catch(e) {}
    return p;
  };

  var XHR = window.XMLHttpRequest;
  var open = XHR.prototype.open;
  var send = XHR.prototype.send;
  var setHeader = XHR.prototype.setRequestHeader;

  XHR.prototype.open = function(method, url){
    this.__fcw = {url:url, headers:{}};
    return open.apply(this, arguments);
  };
  XHR.prototype.setRequestHeader = function(name, value){
    if (this.__fcw) this.__fcw.headers[name] = value;
    return setHeader.apply(this, arguments);
  };
  XHR.prototype.send = function(){
    var info = this.__fcw;
    var self = this;
    if (info && String(info.url).indexOf('/i/api/graphql/') >= 0) {
      this.addEventListener('loadend', function(){ seen(info.url, self.status); });
    }
    if (info && isTarget(info.url) && !window.__fcw_replaying) {
      this.addEventListener('load', function(){
        if (self.status !== 200) return;
        report({url:info.url, headers:info.headers, body:self.responseText});
      });
    }
    return send.apply(this, arguments);
  };
})();
''';

  /// [FollowCaptureWebViewHost] から実表示の WebView を受け取る。
  ///
  /// HeadlessInAppWebView では捕獲はできるものの再送が必ず 404 になる
  /// (ビューポート・ペース・txId 寿命・ct0 ずれはいずれも実測で否定済み)。
  /// 表示中の WebView なら数分後でも 200 が返るため、実表示のものを使う。
  void attach(InAppWebViewController controller) {
    _controller = controller;
    controller.addJavaScriptHandler(
      handlerName: 'onFollowCaptured',
      callback: (args) {
        if (args.isNotEmpty) _onCaptured(args[0].toString());
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onFollowPage',
      callback: (args) {
        if (args.isNotEmpty && !(_fetchCompleter?.isCompleted ?? true)) {
          _fetchCompleter!.complete(args[0].toString());
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onFollowSeen',
      callback: (args) {
        if (args.isNotEmpty && _seenOps.length < 200) {
          _seenOps.add(args[0].toString());
        }
      },
    );
    if (!(_hostReady?.isCompleted ?? true)) _hostReady!.complete();
    debugPrint('[FollowCaptureWebView] ホストの WebView を受け取りました');
    DebugLogService.instance.log('FollowCaptureWebView',
        'ホストの WebView を受け取りました (${Platform.operatingSystem})');
  }

  /// 捕獲を待っている間に X が投げた GraphQL (名前:status)。診断用
  final List<String> _seenOps = [];

  /// ホスト側の onLoadStop から。捕獲が空振りしたとき、そもそもどの
  /// ページに居たのか (ログイン画面に飛ばされた等) を残す
  void noteLoadStop(String? url) {
    if (!DebugLogService.instance.enabled) return;
    DebugLogService.instance
        .log('FollowCaptureWebView', 'onLoadStop: ${url ?? '(null)'}');
  }

  /// ホスト側の onConsoleMessage から
  void noteConsole(ConsoleMessage msg) {
    if (msg.messageLevel != ConsoleMessageLevel.ERROR &&
        msg.messageLevel != ConsoleMessageLevel.WARNING) {
      return;
    }
    final text = msg.message;
    DebugLogService.instance.log('FollowCaptureWebView',
        'console[${msg.messageLevel}]: ${text.length > 300 ? text.substring(0, 300) : text}');
  }

  Completer<void>? _hostReady;

  /// ホストがマウントされるまで待つ。
  /// ジョブ開始 → ルートにホストを差し込む → attach、という順序になるため。
  Future<void> waitForHost(
      {Duration timeout = const Duration(seconds: 15)}) async {
    if (_controller != null) return;
    _hostReady ??= Completer<void>();
    await _hostReady!.future.timeout(timeout);
  }

  void detach() {
    _controller = null;
    _hostReady = null;
    _capturedKey = null;
    _capturedUrl = null;
    _capturedHeaders = null;
    _pendingInitialPage = null;
  }

  /// ホストが畳まれたときに呼ぶ。
  ///
  /// これを呼ばないと、破棄済みの controller を掴んだままになる。
  /// [waitForHost] は controller が非 null なら即座に返すので、
  /// 次の走査が「もう居ない WebView」に fetch を投げて失敗する。
  ///
  /// [controller] を照合するのは、入れ替わりで新しいホストが先に
  /// attach していた場合に、生きているほうを消さないため。
  void detachHost(InAppWebViewController controller) {
    if (!identical(_controller, controller)) return;
    debugPrint('[FollowCaptureWebView] ホストの WebView を手放しました');
    detach();
  }

  Future<void> _ensureWebView() async {
    if (_controller != null) return;
    try {
      await waitForHost();
    } on TimeoutException {
      throw StateError('走査用 WebView を用意できませんでした');
    }
  }

  // ignore: unused_element
  Future<void> _ensureHeadlessWebView() async {
    if (_webView != null && _controller != null) return;

    final created = Completer<void>();

    _webView = HeadlessInAppWebView(
      // サイズを与えないと 0x0 のままになり、X が UA (スマホ) と
      // ビューポートの不整合を bot と判定して 404 を返す。
      // 実機相当の論理ピクセルを渡しておく。
      initialSize: const Size(412, 915),
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: _interceptorScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: platformUserAgent,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'onFollowCaptured',
          callback: (args) {
            if (args.isNotEmpty) _onCaptured(args[0].toString());
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'onFollowPage',
          callback: (args) {
            if (args.isNotEmpty && !(_fetchCompleter?.isCompleted ?? true)) {
              _fetchCompleter!.complete(args[0].toString());
            }
          },
        );
        if (!created.isCompleted) created.complete();
      },
      onLoadStop: (controller, url) {
        // SPA 遷移で user script が効かない場合の保険
        controller.evaluateJavascript(source: _interceptorScript);
      },
      onConsoleMessage: (controller, msg) {
        if (msg.messageLevel == ConsoleMessageLevel.ERROR) {
          DebugLogService.instance.log('FollowCaptureWebView',
              'console error: ${msg.message.length > 200 ? msg.message.substring(0, 200) : msg.message}');
        }
      },
    );

    await _webView!.run();
    await created.future.timeout(const Duration(seconds: 15), onTimeout: () {
      debugPrint('[FollowCaptureWebView] controller 生成がタイムアウト');
    });
  }

  void _onCaptured(String raw) {
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      _capturedUrl = map['url'] as String;
      _capturedHeaders = (map['headers'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, '$v'));

      // 捕獲したリクエストの txId をプールに入れる。
      // X 側で「今まさに 1 回消費された」ので、その時刻を最終使用時刻にする。
      final tx = _capturedHeaders!.entries
          .firstWhere((e) => e.key.toLowerCase() == 'x-client-transaction-id',
              orElse: () => const MapEntry('', ''))
          .value;
      // 採取した瞬間に X 側でその endpoint 用に 1 回消費されている
      if (tx.isNotEmpty && _txIds.length < txPoolSize) {
        _txIds.add(tx);
        final kind = _capturingKind;
        if (kind != null) _txUsedAt[_txKey(kind, tx)] = DateTime.now();
        debugPrint('[FollowCaptureWebView] txId 追加 (${_txIds.length}/$txPoolSize)');
      }

      // 捕獲時のレスポンスをそのまま 1 ページ目として使う
      final body = map['body'] as String? ?? '';
      try {
        final decoded = json.decode(body) as Map<String, dynamic>;
        if (_txIds.length <= 1) {
          // debugPrint だけだとアプリ内のログに残らず、端末の生ログを
          // 読める環境でしか見えない。切り分けの要なので両方に出す
          final layout = FollowListParser.describeFirstUser(decoded);
          debugPrint('[FollowCaptureWebView] 項目配置: $layout');
          DebugLogService.instance
              .log('FollowCaptureWebView', '項目配置: $layout');
        }
        final parsed = FollowListParser.parse(decoded);
        _pendingInitialPage = FollowListPage(
          statusCode: 200,
          users: parsed.users,
          cursor: parsed.cursor,
        );
      } catch (_) {
        _pendingInitialPage = null;
      }

      debugPrint('[FollowCaptureWebView] 捕獲: '
          'users=${_pendingInitialPage?.users.length ?? 0} '
          'headers=${_capturedHeaders?.length} '
          'cursor=${_shorten(_pendingInitialPage?.cursor)} '
          'url=${_shorten(_capturedUrl, 110)}');
      if (!(_captureCompleter?.isCompleted ?? true)) {
        _captureCompleter!.complete();
      }
    } catch (e) {
      debugPrint('[FollowCaptureWebView] 捕獲の解析に失敗: $e');
    }
  }

  // ─── アカウント切替 ───

  Future<void> _switchAccount(XCredentials creds) async {
    if (_currentAuthToken == creds.authToken) return;

    final cookieManager = CookieManager.instance();
    if (_currentAuthToken != null) {
      await _saveCookies(_currentAuthToken!);
    }
    _currentAuthToken = creds.authToken;

    // domain/path 違いの取り残しがあると X が bot 判定するので個別に消す
    await _purgeAllXCookies(cookieManager);

    final saved = _accountCookies[creds.authToken];
    if (saved != null && saved.isNotEmpty) {
      for (final c in saved) {
        await cookieManager.setCookie(
          url: WebUri('https://x.com'),
          name: c.name,
          value: c.value,
          domain: c.domain ?? '.x.com',
          path: c.path ?? '/',
          isSecure: c.isSecure,
          isHttpOnly: c.isHttpOnly,
          expiresDate: c.expiresDate,
        );
      }
    } else {
      for (final pair in creds.allCookies.split('; ')) {
        final eq = pair.indexOf('=');
        if (eq <= 0) continue;
        await cookieManager.setCookie(
          url: WebUri('https://x.com'),
          name: pair.substring(0, eq),
          value: pair.substring(eq + 1),
          domain: '.x.com',
        );
      }
    }
  }

  Future<void> _purgeAllXCookies(CookieManager cookieManager) async {
    for (final urlStr in const ['https://x.com', 'https://twitter.com']) {
      try {
        final cookies = await cookieManager.getCookies(url: WebUri(urlStr));
        for (final c in cookies) {
          try {
            await cookieManager.deleteCookie(
              url: WebUri(urlStr),
              name: c.name,
              domain: c.domain,
              path: c.path ?? '/',
            );
          } catch (_) {}
        }
      } catch (_) {}
      try {
        await cookieManager.deleteCookies(url: WebUri(urlStr));
      } catch (_) {}
    }
  }

  Future<void> _saveCookies(String authToken) async {
    try {
      _accountCookies[authToken] =
          await CookieManager.instance().getCookies(url: WebUri('https://x.com'));
    } catch (e) {
      debugPrint('[FollowCaptureWebView] cookie 保存に失敗: $e');
    }
  }

  // ─── 捕獲 ───

  /// [targetHandle] の [kind] 一覧ページを開き、X 自身のリクエストを捕獲する。
  /// 同じ対象を捕獲済みならそのまま再利用する。
  Future<bool> prepare({
    required Account account,
    required String targetHandle,
    required FollowListKind kind,
    bool force = false,
    CaptureCancelToken? cancelToken,
  }) async {
    final creds = account.xCredentials;
    final key = _key(creds.authToken, targetHandle, kind);
    if (!force && _capturedKey == key && hasCapture) return true;

    await _ensureWebView();
    await _switchAccount(creds);

    _capturedKey = null;
    _capturedUrl = null;
    _capturedHeaders = null;
    _pendingInitialPage = null;
    _capturingKind = kind;
    _seenOps.clear();
    // トークンは endpoint をまたいで使い回せるので、通常は捨てない。
    // 404 からの捕り直し (force) のときだけ作り直す。
    if (force) {
      _txIds.clear();
      _txUsedAt.clear();
    }
    _captureCompleter = Completer<void>();

    final path = kind == FollowListKind.following ? 'following' : 'followers';
    final handle = targetHandle.replaceFirst('@', '');
    final url = WebUri('https://x.com/$handle/$path');
    await _controller!.loadUrl(urlRequest: URLRequest(url: url));

    try {
      await CaptureCancelToken.race(
          _awaitCaptureWithReload(url, handle, path, cancelToken), cancelToken);
    } on TimeoutException {
      String? location;
      try {
        location = (await _controller!
                .evaluateJavascript(source: 'location.href')
                .timeout(const Duration(seconds: 3)))
            ?.toString();
      } catch (_) {}
      DebugLogService.instance.log(
          'FollowCaptureWebView',
          '@$handle/$path の捕獲が ${_captureTimeout.inSeconds}秒でタイムアウト '
          '(${Platform.operatingSystem}) location=$location '
          'seen=[${_seenOps.join(', ')}]');
      return false;
    }

    // 捕獲は「最初の XHR が飛んだ時点」で完了する。X のクライアントはその後も
    // 初期化を続けており、直後に再送すると 404 になることがある。
    // ページが落ち着くまで待ってから使えるようにする。
    await CaptureCancelToken.sleep(_settleDelay, cancelToken);
    cancelToken?.throwIfCancelled();

    await _saveCookies(creds.authToken);
    _capturedKey = key;

    // txId を追加で集める。1 個を使い回すと 404 になるため、
    // 拡張機能と同じくリロードして複数確保しローテーションする。
    await _harvestTokens(cancelToken);

    return hasCapture;
  }

  /// ページをリロードして txId を追加で捕獲する
  Future<void> _harvestTokens([CaptureCancelToken? cancelToken]) async {
    while (_txIds.length < txPoolSize) {
      cancelToken?.throwIfCancelled();
      final before = _txIds.length;
      _captureCompleter = Completer<void>();
      try {
        await _controller!.reload();
        await CaptureCancelToken.race(
            _captureCompleter!.future.timeout(_harvestTimeout), cancelToken);
      } on CaptureCancelledException {
        rethrow;
      } on TimeoutException {
        debugPrint('[FollowCaptureWebView] txId 補充がタイムアウト');
        break;
      } catch (e) {
        debugPrint('[FollowCaptureWebView] txId 補充に失敗: $e');
        break;
      }
      if (_txIds.length == before) {
        // 同じ txId しか返ってこないなら打ち切る
        debugPrint('[FollowCaptureWebView] 新しい txId が取れないので補充終了');
        break;
      }
    }
    debugPrint('[FollowCaptureWebView] txId プール ${_txIds.length} 個');
  }

  /// 指定 endpoint でクールダウン明けの txId を返す。全部冷却中なら明けるまで待つ。
  /// 冷却は endpoint ごとなので、Followers が全部冷えていても
  /// Following では同じトークンがすぐ使える。
  Future<String?> _pickTxId(FollowListKind kind,
      [CaptureCancelToken? cancelToken]) async {
    if (_txIds.isEmpty) return null;
    final cooldown = txCooldownOf(kind);
    while (true) {
      // Followers の冷却は 60 秒ある。ここでキャンセルを見ないと
      // 中断ボタンを押してから最大 1 分止まらない
      cancelToken?.throwIfCancelled();
      final now = DateTime.now();
      String? best;
      DateTime? bestUsed;
      var minWait = cooldown;
      for (final tx in _txIds) {
        final used = _txUsedAt[_txKey(kind, tx)];
        if (used == null) return tx; // その endpoint では未使用
        final elapsed = now.difference(used);
        if (elapsed >= cooldown) {
          if (bestUsed == null || used.isBefore(bestUsed)) {
            best = tx;
            bestUsed = used;
          }
        } else {
          final wait = cooldown - elapsed;
          if (wait < minWait) minWait = wait;
        }
      }
      if (best != null) return best;
      await CaptureCancelToken.sleep(minWait, cancelToken);
    }
  }

  // ─── 再送 ───

  /// 捕獲したリクエストの cursor だけ差し替えてページ内で再送する。
  ///
  /// 404 は txId 失効の可能性が高いので、一度だけ捕り直して再試行する。
  Future<FollowListPage> fetchPage({
    required Account account,
    required String targetHandle,
    required FollowListKind kind,
    String? cursor,
    CaptureCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    if (!hasCapture) {
      final ok = await prepare(
          account: account,
          targetHandle: targetHandle,
          kind: kind,
          cancelToken: cancelToken);
      if (!ok) {
        throw StateError('Followers リクエストを捕獲できませんでした');
      }
    }

    // 捕獲時のレスポンスを 1 ページ目として消費する (無駄撃ちを避ける)
    if (cursor == null && _pendingInitialPage != null) {
      final page = _pendingInitialPage!;
      _pendingInitialPage = null;
      return page;
    }

    var page = await _runPageFetch(cursor, kind, cancelToken);

    if (page.statusCode == 404) {
      cancelToken?.throwIfCancelled();
      debugPrint('[FollowCaptureWebView] 404 → txId 失効とみて捕り直す');
      DebugLogService.instance
          .log('FollowCaptureWebView', '404 → 再捕獲を試みる');
      final ok = await prepare(
          account: account,
          targetHandle: targetHandle,
          kind: kind,
          force: true,
          cancelToken: cancelToken);
      if (ok) {
        // 捕り直した直後の 1 ページ目は使わずに、目的の cursor を取りに行く
        _pendingInitialPage = null;
        page = await _runPageFetch(cursor, kind, cancelToken);
      }
    }
    return page;
  }

  /// 捕獲を待つ。何も通信が来ないまま [_reloadAfter] が過ぎたら開き直す。
  ///
  /// 「待てばそのうち来る」ではなく「来ないときは永遠に来ない」ので、
  /// 待ち時間を延ばすだけでは解決しない。人がページを再読み込みするのと
  /// 同じことをする。
  Future<void> _awaitCaptureWithReload(
    WebUri url,
    String handle,
    String path,
    CaptureCancelToken? cancelToken,
  ) async {
    final deadline = DateTime.now().add(_captureTimeout);
    var reloads = 0;

    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) throw TimeoutException(path);

      final slice = remaining < _reloadAfter ? remaining : _reloadAfter;
      try {
        await _captureCompleter!.future.timeout(slice);
        return; // 捕獲できた
      } on TimeoutException {
        cancelToken?.throwIfCancelled();

        // 何か通信は起きているなら、ページは動いている。開き直すと
        // かえって遠回りになるので待ち続ける
        if (_seenOps.isNotEmpty) continue;
        if (reloads >= _maxReloads) continue;

        reloads++;
        DebugLogService.instance.log(
            'FollowCaptureWebView',
            '@$handle/$path が ${slice.inSeconds}秒 無通信のため読み込み直す '
            '($reloads/$_maxReloads)');
        try {
          // キャッシュから描画されて何も起きない状態を抜けたいので、
          // reload ではなく URL を指定し直す
          await _controller!.loadUrl(urlRequest: URLRequest(url: url));
        } catch (e) {
          DebugLogService.instance
              .log('FollowCaptureWebView', '読み込み直しに失敗: $e');
        }
      }
    }
  }

  /// 捕獲時の ct0 は古くなっている可能性がある。X が ct0 をローテートすると
  /// ヘッダーの x-csrf-token と実際に送られる Cookie がずれて弾かれるため、
  /// 送信直前に現在の Cookie から読み直して上書きする。
  Future<Map<String, String>> _headersWithFreshCt0(String? txId) async {
    final headers = Map<String, String>.from(_capturedHeaders!);

    // ★ 毎リクエストで別の txId に差し替える (使い回すと 404)
    if (txId != null) {
      headers.removeWhere((k, _) => k.toLowerCase() == 'x-client-transaction-id');
      headers['x-client-transaction-id'] = txId;
    }
    headers['x-twitter-active-user'] = 'yes';

    try {
      final cookies =
          await CookieManager.instance().getCookies(url: WebUri('https://x.com'));
      for (final c in cookies) {
        if (c.name == 'ct0') {
          final ct0 = '${c.value}';
          if (headers['x-csrf-token'] != ct0) {
            debugPrint('[FollowCaptureWebView] ct0 が変わっていたので更新');
            headers['x-csrf-token'] = ct0;
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('[FollowCaptureWebView] ct0 の読み直しに失敗: $e');
    }
    return headers;
  }

  Future<FollowListPage> _runPageFetch(String? cursor, FollowListKind kind,
      [CaptureCancelToken? cancelToken]) async {
    final url = cursor == null
        ? _capturedUrl!
        : FollowListParser.replaceCursorInUrl(_capturedUrl!, cursor);
    final txId = await _pickTxId(kind, cancelToken);
    final headers = await _headersWithFreshCt0(txId);
    if (txId != null) _txUsedAt[_txKey(kind, txId)] = DateTime.now();

    final map = await _rawFetch(url, headers, cancelToken);
    final status = map['status'] as int;
    if (status == -1) {
      throw StateError('ページ内 fetch が失敗: ${map['error']}');
    }

    if (status != 200) {
      final body = map['body'] as String? ?? '';
      debugPrint('[FollowCaptureWebView] $status '
          'cursor=${_shorten(cursor)} url=${_shorten(url, 110)}');
      debugPrint('[FollowCaptureWebView]   body=${_shorten(body, 200)}');
    }

    final rateLimit = _rateLimitOf(map);
    if (status != 200) {
      return FollowListPage(statusCode: status, rateLimit: rateLimit);
    }

    try {
      final body = json.decode(map['body'] as String) as Map<String, dynamic>;
      final parsed = FollowListParser.parse(body);
      if (parsed.skipped > 0) {
        debugPrint('[FollowCaptureWebView] ⚠ 解析できないユーザー '
            '${parsed.skipped}件 (取りこぼし)');
      }
      return FollowListPage(
        statusCode: 200,
        users: parsed.users,
        cursor: parsed.cursor,
        rateLimit: rateLimit,
      );
    } on FormatException {
      return FollowListPage(
          statusCode: FollowListPage.badJson, rateLimit: rateLimit);
    }
  }

  static XRateLimit? _rateLimitOf(Map<String, dynamic> map) =>
      XRateLimit.fromHeaders({
        if (map['limit'] != null) 'x-rate-limit-limit': '${map['limit']}',
        if (map['remaining'] != null)
          'x-rate-limit-remaining': '${map['remaining']}',
        if (map['reset'] != null) 'x-rate-limit-reset': '${map['reset']}',
      });

  /// ページ内で 1 回 fetch して、status・レート制限ヘッダー・本文を返す
  Future<Map<String, dynamic>> _rawFetch(
      String url, Map<String, String> headers,
      [CaptureCancelToken? cancelToken]) async {
    _fetchCompleter = Completer<String>();
    final source = '''
(async function(){
  window.__fcw_replaying = true;
  try {
    var res = await fetch(${json.encode(url)}, {
      method: 'GET',
      headers: ${json.encode(headers)},
      credentials: 'include'
    });
    var body = await res.text();
    window.flutter_inappwebview.callHandler('onFollowPage', JSON.stringify({
      status: res.status,
      limit: res.headers.get('x-rate-limit-limit'),
      remaining: res.headers.get('x-rate-limit-remaining'),
      reset: res.headers.get('x-rate-limit-reset'),
      body: body
    }));
  } catch(e) {
    window.flutter_inappwebview.callHandler('onFollowPage', JSON.stringify({
      status: -1, error: String(e)
    }));
  } finally {
    window.__fcw_replaying = false;
  }
})();
''';
    await _controller!.evaluateJavascript(source: source);

    final String raw;
    try {
      raw = await CaptureCancelToken.race(
          _fetchCompleter!.future.timeout(_fetchTimeout), cancelToken);
    } on TimeoutException {
      // エンジン側のネットワークエラー扱いに載せる
      throw TimeoutException('ページ内 fetch がタイムアウト', _fetchTimeout);
    }

    return json.decode(raw) as Map<String, dynamic>;
  }

  // ─── 並列化の可否を測る診断 ───

  /// Following と Followers を並列に走らせられるかを実測する。
  ///
  /// 確かめたいのは 3 点:
  ///   ① レート制限の枠が operation ごとに別か（共通なら並列に意味がない）
  ///   ② txId がパスに紐づくか（別ならプールを 2 つ持つ必要がある）
  ///   ③ ページ URL と違うパスへ再送できるか（できないと種別ごとに遷移が要る）
  Future<String> probeParallelFeasibility({
    required Account account,
    required String targetHandle,
  }) async {
    final log = <String>[];
    void note(String s) {
      log.add(s);
      debugPrint('[Probe] $s');
    }

    int? remainingOf(Map<String, dynamic> m) =>
        int.tryParse('${m['remaining']}');

    // 採取した txId は「その瞬間に X 側で 1 回使われている」ので、
    // 冷却を待たずに撃つと再利用扱いで 404 になる。
    // 前回の測定はここを守っておらず ③ の判定が汚れた。
    Future<void> cool(String why) async {
      note('   \$why: txId 冷却待ち \${txCooldownFollowers.inSeconds}秒');
      await Future.delayed(txCooldownFollowers);
    }

    // --- Followers 側を捕獲 (ページは /followers) ---
    if (!await prepare(
        account: account,
        targetHandle: targetHandle,
        kind: FollowListKind.followers)) {
      return 'Followers の捕獲に失敗';
    }
    final fUrl = _capturedUrl!;
    final fHeaders = Map<String, String>.from(_capturedHeaders!);
    final fTx = _txIds.toList();

    await cool('①の前');
    final f1 = await _rawFetch(fUrl, _withTx(fHeaders, fTx.first));
    final f1Rem = remainingOf(f1);
    note('① Followers 実行(ページ=/followers): '
        'status=${f1['status']} 残=$f1Rem/${f1['limit']}');
    if (f1['status'] != 200) {
      note('   ⚠ 基準となる Followers が通っていないので、以降の判定は参考値');
    }

    // --- Following 側を捕獲 (ページが /following に移る) ---
    if (!await prepare(
        account: account,
        targetHandle: targetHandle,
        kind: FollowListKind.following)) {
      return log.join('\n') + '\nFollowing の捕獲に失敗';
    }
    final gUrl = _capturedUrl!;
    final gHeaders = Map<String, String>.from(_capturedHeaders!);
    final gTx = _txIds.toList();

    // ② Followers 用の txId で Following を叩く → 404 ならパス紐づき
    final wrong = await _rawFetch(gUrl, _withTx(gHeaders, fTx[1]));
    note('② Followers の txId で Following: status=${wrong['status']}'
        '${wrong['status'] == 404 ? ' → txId はパスに紐づく（プールは別に必要）' : ' → パス非依存'}');

    // 正しい txId で Following
    final g1 = await _rawFetch(gUrl, _withTx(gHeaders, gTx.first));
    note('   Following 実行: status=${g1['status']} '
        '残=${remainingOf(g1)}/${g1['limit']}');

    // ③ ページは /following のまま Followers を叩く。
    //    ここが本題なので、必ず冷えた txId を使う
    await cool('③の前');
    final cross = await _rawFetch(fUrl, _withTx(fHeaders, fTx.last));
    final f2Rem = remainingOf(cross);
    note('③ ページ=/following のまま Followers: status=${cross['status']}'
        '${cross['status'] == 200 ? ' → ページ URL と違うパスでも通る（真の並列が可能）' : ' → 種別ごとにページ遷移が必要'}');

    // ④ クールダウンは endpoint ごとに独立しているか。
    //    独立していれば、同じ 3 個の txId を Followers と Following で
    //    そのまま共用できる = Following の追加コストがゼロになる。
    //    ③ で fTx.last を Followers に使った直後の状態で試す。
    final sameTxOtherPath = await _rawFetch(gUrl, _withTx(gHeaders, fTx.last));
    note('④ 同じ txId を直後に Following へ: status=${sameTxOtherPath['status']}'
        '${sameTxOtherPath['status'] == 200 ? ' → 冷却は endpoint ごと。共用できる（Following はタダ）' : ' → 冷却は txId 単位。共用すると Followers が遅くなる'}');

    final sameTxSamePath = await _rawFetch(fUrl, _withTx(fHeaders, fTx.last));
    note('   対照: 同じ txId を直後に Followers へ: '
        'status=${sameTxSamePath['status']}'
        '${sameTxSamePath['status'] == 404 ? ' (想定どおり弾かれる)' : ' (弾かれない…要再考)'}');

    // ① の判定: Followers の残量が、自分の Followers 呼び出しぶんしか減っていないか
    if (f1Rem != null && f2Rem != null) {
      final drop = f1Rem - f2Rem;
      note('① 判定: Followers 残量 $f1Rem → $f2Rem (−$drop)。'
          '間に Following を ${1 + gTx.length + 1} 回叩いている。'
          '${drop <= 1 ? ' → 枠は operation ごとに別。並列化の効果あり' : ' → 枠が共通の疑い。並列化しても速くならない'}');
    }

    await reset();
    return log.join('\n');
  }

  Map<String, String> _withTx(Map<String, String> headers, String tx) {
    final h = Map<String, String>.from(headers);
    h.removeWhere((k, _) => k.toLowerCase() == 'x-client-transaction-id');
    h['x-client-transaction-id'] = tx;
    h['x-twitter-active-user'] = 'yes';
    return h;
  }

  static String _shorten(String? value, [int max = 24]) {
    if (value == null || value.isEmpty) return '(なし)';
    return value.length > max ? '${value.substring(0, max)}…' : value;
  }

  /// 走査が終わったら捕獲状態を捨てる。
  /// WebView 自体はホストウィジェットの持ち物なので触らない。
  Future<void> reset() async {
    _capturedKey = null;
    _capturedUrl = null;
    _capturedHeaders = null;
    _pendingInitialPage = null;
    _txIds.clear();
    _txUsedAt.clear();
    _capturingKind = null;
    try {
      await _controller?.loadUrl(
          urlRequest: URLRequest(url: WebUri('about:blank')));
    } catch (_) {}
  }
}
