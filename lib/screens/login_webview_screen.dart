import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/sns_service.dart';
import '../services/debug_log_service.dart';
import '../utils/app_snackbar.dart';
import '../services/x_api_service.dart';
import '../services/x_bearer_token_service.dart';
import '../services/x_features_service.dart';
import '../services/x_query_id_service.dart';

/// ログイン完了時に返す認証情報
class LoginResult {
  const LoginResult({
    required this.service,
    required this.credentials,
    required this.displayName,
    required this.handle,
    this.avatarUrl,
    this.isProtected = false,
  });

  final SnsService service;
  final SnsCredentials credentials;
  final String displayName;
  final bool isProtected;
  final String handle;
  final String? avatarUrl;
}

/// ログイン用 WebView 画面
/// 旧 WebViewTabScreen と同じ構成で、ログイン完了後にユーザーが「完了」ボタンを押す
class LoginWebViewScreen extends StatefulWidget {
  const LoginWebViewScreen({super.key, required this.service});

  final SnsService service;

  @override
  State<LoginWebViewScreen> createState() => _LoginWebViewScreenState();
}

/// X の fetch をインターセプトしてユーザー情報・BearerToken・queryIdをキャプチャするスクリプト
const _xFetchInterceptorScript = '''
(function() {
  window.__xCapturedUser = null;
  window.__xCapturedBearerToken = '';
  window.__xCapturedQueryIds = {};
  var _origFetch = window.fetch;
  window.fetch = function() {
    var url = '';
    if (typeof arguments[0] === 'string') {
      url = arguments[0];
    } else if (arguments[0] && arguments[0].url) {
      url = arguments[0].url;
    }

    // リクエストヘッダーから Bearer Token をキャプチャ
    try {
      var opts = arguments[1] || {};
      var headers = opts.headers || {};
      var authHeader = '';
      if (typeof headers.get === 'function') {
        authHeader = headers.get('Authorization') || headers.get('authorization') || '';
      } else {
        authHeader = headers['Authorization'] || headers['authorization'] || '';
      }
      if (authHeader.indexOf('Bearer ') === 0 && authHeader.length > 20) {
        window.__xCapturedBearerToken = authHeader.substring(7);
      }
    } catch(e) {}

    // URL から queryId をキャプチャ
    var gqlMatch = url.match(/\\/i\\/api\\/graphql\\/([A-Za-z0-9_-]+)\\/([A-Za-z0-9_]+)/);
    if (gqlMatch) {
      window.__xCapturedQueryIds[gqlMatch[2]] = gqlMatch[1];
    }

    return _origFetch.apply(this, arguments).then(function(response) {
      try {
        // settings API のレスポンスをキャプチャ
        if (url.indexOf('/account/settings') !== -1 && response.ok) {
          response.clone().json().then(function(data) {
            if (data && data.screen_name) {
              window.__xCapturedUser = window.__xCapturedUser || {};
              window.__xCapturedUser.screenName = data.screen_name;
            }
          }).catch(function(){});
        }
        // UserByScreenName のレスポンスをキャプチャ
        if (url.indexOf('/UserByScreenName') !== -1 && response.ok) {
          response.clone().json().then(function(data) {
            try {
              var u = data.data.user.result;
              var legacy = u.legacy || {};
              window.__xCapturedUser = window.__xCapturedUser || {};
              window.__xCapturedUser.screenName = legacy.screen_name || window.__xCapturedUser.screenName;
              window.__xCapturedUser.name = legacy.name;
              window.__xCapturedUser.avatar = (legacy.profile_image_url_https || '').replace('_normal', '_400x400');
            } catch(e) {}
          }).catch(function(){});
        }
        // HomeTimeline / HomeLatestTimeline からログインユーザーの情報を探す
        if ((url.indexOf('/HomeTimeline') !== -1 || url.indexOf('/HomeLatestTimeline') !== -1) && response.ok) {
          response.clone().json().then(function(data) {
            try {
              // レスポンスの viewer フィールドを探す
              if (data && data.data && data.data.viewer) {
                var v = data.data.viewer;
                window.__xCapturedUser = window.__xCapturedUser || {};
                if (v.screen_name) window.__xCapturedUser.screenName = v.screen_name;
                if (v.name) window.__xCapturedUser.name = v.name;
              }
            } catch(e) {}
          }).catch(function(){});
        }
        // Viewer クエリのレスポンス
        if (url.indexOf('/Viewer') !== -1 && response.ok) {
          response.clone().json().then(function(data) {
            try {
              var v = data.data.viewer;
              if (v) {
                var legacy = v.legacy || v;
                window.__xCapturedUser = window.__xCapturedUser || {};
                window.__xCapturedUser.screenName = legacy.screen_name || v.screen_name;
                window.__xCapturedUser.name = legacy.name || v.name;
                window.__xCapturedUser.avatar = (legacy.profile_image_url_https || '').replace('_normal', '_400x400');
              }
            } catch(e) {}
          }).catch(function(){});
        }
      } catch(e) {}
      return response;
    });
  };
})();
''';

class _LoginWebViewScreenState extends State<LoginWebViewScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _isExtracting = false;
  // WebViewのリクエストからBearerTokenとqueryIdを自動キャプチャ
  String? _capturedBearerToken;
  final Map<String, String> _capturedQueryIds = {};

  // 取得状況表示用
  String _extractStatus = '認証情報を取得中…';
  bool _gotBearerToken = false;
  bool _gotQueryIds = false;
  bool _gotUserInfo = false;
  bool _gotNotifications = false;
  bool _cookiesCleared = false;
  bool _loginDetected = false;
  bool _pageReady = false;

  Widget _buildStatusRow(String label, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Icon(
              done ? Icons.check_circle : Icons.hourglass_empty,
              size: 16,
              color: done ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, color: done ? Colors.green : Colors.grey)),
        ],
      ),
    );
  }

  void _updateExtractStatus(String status, {bool? bearerToken, bool? queryIds, bool? userInfo, bool? notifications}) {
    if (!mounted) return;
    setState(() {
      _extractStatus = status;
      if (bearerToken != null) _gotBearerToken = bearerToken;
      if (queryIds != null) _gotQueryIds = queryIds;
      if (userInfo != null) _gotUserInfo = userInfo;
      if (notifications != null) _gotNotifications = notifications;
    });
  }

  @override
  void initState() {
    super.initState();
    _clearCookiesBeforeLogin();
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }

  /// ログイン前に該当ドメインの Cookie をクリア（他アカウントと干渉しないように）
  Future<void> _clearCookiesBeforeLogin() async {
    final cookieManager = CookieManager.instance();
    // 全 Cookie を削除（ドメイン指定だとサブドメイン Cookie が残る場合がある）
    await cookieManager.deleteAllCookies();
    // WebView のキャッシュ・ストレージもクリア
    await InAppWebViewController.clearAllCache();
    // localStorage / sessionStorage もクリア（Bluesky の BSKY_STORAGE 等）
    final webStorageManager = WebStorageManager.instance();
    await webStorageManager.android.deleteAllData();
    if (mounted) {
      setState(() => _cookiesCleared = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.service.label} にログイン'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // ログイン完了ボタン
          TextButton.icon(
            onPressed: _isExtracting ? null : _onDonePressed,
            icon: const Icon(Icons.check),
            label: const Text('完了'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
        children: [
          if (_progress < 1.0) LinearProgressIndicator(value: _progress),
          Expanded(
            child: !_cookiesCleared
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
              // Cookie クリア後にログインページを開く
              initialUrlRequest: URLRequest(
                url: WebUri(widget.service.homeUrl),
              ),
              initialSettings: InAppWebViewSettings(
                userAgent:
                    'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/131.0.0.0 Mobile Safari/537.36',
                javaScriptEnabled: true,
                domStorageEnabled: true,
                useShouldOverrideUrlLoading: true,
                thirdPartyCookiesEnabled: true,
                javaScriptCanOpenWindowsAutomatically: true,
                supportMultipleWindows: true,
              ),
              // Google OAuth: ポップアップウィンドウ内のWebViewを作成し、
              // 認証完了後にpostMessageで親に返すフローを処理
              onCreateWindow: (controller, createWindowAction) async {
                showDialog(
                  context: context,
                  builder: (ctx) => Dialog(
                    insetPadding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: double.infinity,
                        height: MediaQuery.of(context).size.height * 0.8,
                        child: InAppWebView(
                          windowId: createWindowAction.windowId,
                          initialSettings: InAppWebViewSettings(
                            userAgent:
                                'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
                                'AppleWebKit/537.36 (KHTML, like Gecko) '
                                'Chrome/131.0.0.0 Mobile Safari/537.36',
                            javaScriptEnabled: true,
                            domStorageEnabled: true,
                            thirdPartyCookiesEnabled: true,
                          ),
                          onLoadStop: (ctrl, url) {
                            final urlStr = url?.toString() ?? '';
                            debugPrint('[LoginWebView] popup onLoadStop: $urlStr');
                          },
                          onCloseWindow: (ctrl) {
                            // 認証完了でpostMessageが親に返り、ポップアップが閉じられた
                            debugPrint('[LoginWebView] popup onCloseWindow');
                            if (Navigator.of(ctx).canPop()) {
                              Navigator.of(ctx).pop();
                            }
                            // 親WebViewをリロードし、少し待ってからcookieを確認
                            controller.loadUrl(
                              urlRequest: URLRequest(url: WebUri('https://x.com/home')),
                            );
                            Future.delayed(const Duration(seconds: 3), () {
                              if (mounted) _checkLoginState();
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                );
                return true;
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final url = navigationAction.request.url?.toString() ?? '';
                debugPrint('[LoginWebView] shouldOverrideUrlLoading: $url');
                return NavigationActionPolicy.ALLOW;
              },
              onLoadError: (controller, url, code, message) {
                debugPrint('[LoginWebView] onLoadError: $url code=$code msg=$message');
              },
              onReceivedHttpError: (controller, request, response) {
                debugPrint('[LoginWebView] HTTP error: ${request.url} status=${response.statusCode}');
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint('[LoginWebView] console: ${consoleMessage.message}');
              },
              // X の場合: fetch をインターセプトしてユーザー情報をキャプチャ
              initialUserScripts: widget.service == SnsService.x
                  ? UnmodifiableListView([
                      UserScript(
                        source: _xFetchInterceptorScript,
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                    ])
                  : null,
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onProgressChanged: (_, progress) {
                setState(() => _progress = progress / 100);
              },
              // WebViewのリクエストからqueryIdを自動キャプチャ
              onLoadResource: (controller, resource) {
                final url = resource.url?.toString() ?? '';
                // GraphQL queryId
                final gqlMatch = RegExp(r'/i/api/graphql/([A-Za-z0-9_-]+)/([A-Za-z0-9_]+)').firstMatch(url);
                if (gqlMatch != null) {
                  _capturedQueryIds[gqlMatch.group(2)!] = gqlMatch.group(1)!;
                  // features パラメータもキャプチャ
                  final uri = Uri.tryParse(url);
                  final featuresParam = uri?.queryParameters['features'];
                  if (featuresParam != null) {
                    try {
                      final features = json.decode(featuresParam) as Map<String, dynamic>;
                      XFeaturesService.instance.updateFeatures(gqlMatch.group(2)!, features);
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (controller, url) {
                debugPrint('[LoginWebView] onLoadStop: $url');
                if (!_pageReady && mounted) {
                  setState(() => _pageReady = true);
                }
                final urlStr = url?.toString() ?? '';
                if (urlStr.contains(widget.service.domain)) {
                  debugPrint('[LoginWebView] Returned to ${widget.service.domain}');
                  // ログイン自動検知
                  _checkLoginState();
                }
                // X の場合: fetch interceptor を再注入
                if (widget.service == SnsService.x &&
                    urlStr.contains('x.com')) {
                  controller.evaluateJavascript(
                    source: _xFetchInterceptorScript,
                  );
                }
              },
            ),
          ),
        ],
      ),
          // ページロード待ちオーバーレイ
          if (_cookiesCleared && !_pageReady)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('ログイン画面を準備中...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          // 認証情報取得オーバーレイ
          if (_isExtracting)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: widget.service == SnsService.x
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text(
                          _extractStatus,
                          style: const TextStyle(fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        if (widget.service == SnsService.x) ...[
                          const SizedBox(height: 16),
                          _buildStatusRow('Bearer Token', _gotBearerToken),
                          _buildStatusRow('queryId', _gotQueryIds),
                          _buildStatusRow('ユーザー情報', _gotUserInfo),
                          _buildStatusRow('通知 queryId', _gotNotifications),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// ログイン状態を自動チェックしてモーダルを表示
  Future<void> _checkLoginState() async {
    if (_loginDetected || _isExtracting) return;

    bool loggedIn = false;

    if (widget.service == SnsService.x) {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri('https://x.com'),
      );
      final hasAuth = cookies.any((c) => c.name == 'auth_token');
      final hasCt0 = cookies.any((c) => c.name == 'ct0');
      loggedIn = hasAuth && hasCt0;
    } else {
      // Bluesky: ログイン後にbsky.appドメインでセッション情報がlocalStorageに保存される
      if (_controller != null) {
        final session = await _controller!.evaluateJavascript(
          source: 'localStorage.getItem("BSKY_STORAGE") || ""',
        );
        loggedIn = session != null && session.toString().contains('accessJwt');
      }
    }

    if (!loggedIn || !mounted) return;

    _loginDetected = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('ログインを確認しました'),
        content: const Text('このアカウントを追加しますか？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _loginDetected = false; // キャンセル後に再検知可能に
            },
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _onDonePressed();
            },
            child: const Text('アカウントを追加'),
          ),
        ],
      ),
    );
  }

  /// ユーザーが「完了」ボタンを押した時の処理
  Future<void> _onDonePressed() async {
    setState(() => _isExtracting = true);

    try {
      switch (widget.service) {
        case SnsService.bluesky:
          await _extractBlueskyCredentials();
        case SnsService.x:
          await _extractXCredentials();
      }
    } catch (e) {
      debugPrint('[LoginWebView] Error: $e');
      if (mounted) {
        showAppSnackBar(context, '認証情報の取得に失敗しました: $e', type: SnackType.error);
      }
    }

    if (mounted) {
      setState(() => _isExtracting = false);
    }
  }

  // =============================================
  // Bluesky
  // =============================================

  Future<void> _extractBlueskyCredentials() async {
    final result = await _controller?.evaluateJavascript(
      source: '''
        (function() {
          try {
            var storage = localStorage.getItem('BSKY_STORAGE');
            if (storage) return storage;
            var root = localStorage.getItem('root');
            if (root) return root;
            for (var i = 0; i < localStorage.length; i++) {
              var key = localStorage.key(i);
              var val = localStorage.getItem(key);
              if (val && val.includes('accessJwt')) return val;
            }
            return null;
          } catch(e) { return null; }
        })()
      ''',
    );

    if (result == null || result == 'null') {
      if (mounted) {
        showAppSnackBar(context, 'Bluesky にログインしてから「完了」を押してください', type: SnackType.info);
      }
      return;
    }

    final data = json.decode(result is String ? result : result.toString());

    Map<String, dynamic>? session;
    if (data is Map<String, dynamic>) {
      session = _findSession(data);
    }

    if (session == null) {
      if (mounted) {
        showAppSnackBar(context, 'セッション情報が見つかりませんでした', type: SnackType.error);
      }
      return;
    }

    debugPrint('[LoginWebView] Bluesky session: ${session['handle']}');

    final creds = BlueskyCredentials(
      accessJwt: session['accessJwt'] as String,
      refreshJwt: session['refreshJwt'] as String,
      did: session['did'] as String,
      handle: session['handle'] as String,
    );

    // セッションからアバターを試みる
    String? avatarUrl = session['avatar'] as String?;
    String displayName = session['displayName'] as String? ?? creds.handle;

    // アバターがなければ getProfile API で取得
    if (avatarUrl == null || avatarUrl.isEmpty) {
      try {
        final profileResp = await http.get(
          Uri.parse(
            '${creds.pdsUrl}/xrpc/app.bsky.actor.getProfile'
            '?actor=${Uri.encodeComponent(creds.did)}',
          ),
          headers: {
            'Authorization': 'Bearer ${creds.accessJwt}',
            'Accept': 'application/json',
          },
        );
        debugPrint('[LoginWebView] Bluesky getProfile status: ${profileResp.statusCode}');
        if (profileResp.statusCode == 200) {
          final profile =
              json.decode(profileResp.body) as Map<String, dynamic>;
          avatarUrl = profile['avatar'] as String?;
          final dn = profile['displayName'] as String?;
          if (dn != null && dn.isNotEmpty) displayName = dn;
          debugPrint('[LoginWebView] Bluesky avatar: $avatarUrl');
        }
      } catch (e) {
        debugPrint('[LoginWebView] Error fetching Bluesky profile: $e');
      }
    }

    final loginResult = LoginResult(
      service: SnsService.bluesky,
      credentials: creds,
      displayName: displayName,
      handle: '@${creds.handle}',
      avatarUrl: avatarUrl,
    );

    // Cookie クリア (次回ログイン用)
    await CookieManager.instance().deleteAllCookies();

    if (mounted) Navigator.of(context).pop(loginResult);
  }

  Map<String, dynamic>? _findSession(Map<String, dynamic> data) {
    if (data.containsKey('accessJwt') && data.containsKey('did')) {
      return data;
    }
    for (final key in ['session', 'currentAccount']) {
      if (data.containsKey(key)) {
        final v = data[key];
        if (v is Map<String, dynamic>) {
          final found = _findSession(v);
          if (found != null) return found;
        }
      }
    }
    if (data.containsKey('accounts')) {
      final accounts = data['accounts'];
      if (accounts is List) {
        for (final a in accounts) {
          if (a is Map<String, dynamic> && a.containsKey('accessJwt')) {
            return a;
          }
        }
      }
    }
    for (final value in data.values) {
      if (value is Map<String, dynamic>) {
        final found = _findSession(value);
        if (found != null) return found;
      }
    }
    return null;
  }

  // =============================================
  // X
  // =============================================

  Future<void> _extractXCredentials() async {
    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(
      url: WebUri('https://x.com'),
    );

    String? authToken;
    String? ct0;
    String? twid;
    final cookieParts = <String>[];

    for (final cookie in cookies) {
      cookieParts.add('${cookie.name}=${cookie.value}');
      if (cookie.name == 'auth_token') {
        authToken = cookie.value.toString();
      } else if (cookie.name == 'ct0') {
        ct0 = cookie.value.toString();
      } else if (cookie.name == 'twid') {
        twid = cookie.value.toString();
      }
    }

    final allCookies = cookieParts.join('; ');
    debugPrint('[LoginWebView] X cookies: '
        'auth_token=${authToken != null}, ct0=${ct0 != null}, total=${cookies.length}');

    if (authToken == null || ct0 == null) {
      if (mounted) {
        showAppSnackBar(context, 'X にログインしてから「完了」を押してください', type: SnackType.info);
      }
      return;
    }

    final creds = XCredentials(authToken: authToken, ct0: ct0, allCookies: allCookies);
    final _log = DebugLogService.instance;

    // === 1. onLoadResource で queryId がキャプチャされるのを待つ ===
    _updateExtractStatus('API応答を待っています…');
    for (var i = 0; i < 16; i++) {
      if (_capturedQueryIds.isNotEmpty) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // キャプチャ済みqueryIdを保存
    if (_capturedQueryIds.isNotEmpty) {
      await XQueryIdService.instance.updateQueryIds(creds, _capturedQueryIds);
    }
    await _log.log('Login', 'capturedQueryIds: ${_capturedQueryIds.keys.join(",")}');

    // === 2. BearerToken 確認 ===
    if (!XBearerTokenService.instance.hasToken) {
      await XBearerTokenService.instance.init();
    }
    _updateExtractStatus('取得状況を確認中…',
      bearerToken: XBearerTokenService.instance.hasToken,
    );

    // === 3. 不足queryIdをJSバンドルから補完 ===
    _updateExtractStatus('queryId を取得中…');
    await XQueryIdService.instance.refreshQueryIds(creds);

    // 主要queryIdが揃っているか確認
    final requiredOps = ['HomeLatestTimeline', 'UserByRestId', 'TweetDetail'];
    final allQueryIdsOk = requiredOps.every(
      (op) => XQueryIdService.instance.getQueryId(op, creds: creds).isNotEmpty,
    );
    _updateExtractStatus('queryId を取得中…', queryIds: allQueryIdsOk);

    final missingOps = requiredOps
        .where((op) => XQueryIdService.instance.getQueryId(op, creds: creds).isEmpty)
        .toList();
    await _log.log('Login', 'queryIds ok=$allQueryIdsOk missing=$missingOps');

    // === 4. 通知ページに遷移してNotificationsTimeline queryIdを取得 ===
    final notifQueryId = XQueryIdService.instance.getQueryId('NotificationsTimeline', creds: creds);
    if (notifQueryId.isEmpty && _controller != null) {
      _updateExtractStatus('通知 queryId を取得中…');
      await _controller!.loadUrl(urlRequest: URLRequest(url: WebUri('https://x.com/notifications')));
      for (var i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (_capturedQueryIds.containsKey('NotificationsTimeline')) {
          await XQueryIdService.instance.updateQueryIds(creds, _capturedQueryIds);
          break;
        }
      }
    }
    _updateExtractStatus('通知 queryId を取得中…',
      notifications: XQueryIdService.instance.getQueryId('NotificationsTimeline', creds: creds).isNotEmpty,
    );
    await _log.log('Login', 'NotificationsTimeline=${XQueryIdService.instance.getQueryId("NotificationsTimeline", creds: creds)}');

    // === 5. ユーザー情報取得 ===
    _updateExtractStatus('ユーザー情報を取得中…');
    String displayName = 'X User';
    String handle = '@user';
    String? avatarUrl;
    bool isProtected = false;

    final bearerToken = XBearerTokenService.instance.token;

    // WebView JS で UserByRestId を呼んでユーザー情報を取得
    String? userId;
    if (twid != null) {
      final decoded = Uri.decodeComponent(twid);
      final match = RegExp(r'u=(\d+)').firstMatch(decoded);
      userId = match?.group(1);
    }
    final queryId = XQueryIdService.instance.getQueryId('UserByRestId', creds: creds);

    if (userId != null && _controller != null && bearerToken.isNotEmpty && queryId.isNotEmpty) {
      try {
        final jsResult = await _controller!.callAsyncJavaScript(
          functionBody: '''
            try {
              var resp = await fetch("https://x.com/i/api/graphql/" + queryId_ + "/UserByRestId?variables=" +
                encodeURIComponent(JSON.stringify({userId: userId_, withSafetyModeUserFields: true})) +
                "&features=" + encodeURIComponent(JSON.stringify({
                  hidden_profile_subscriptions_enabled: true, rweb_tipjar_consumption_enabled: true,
                  responsive_web_graphql_exclude_directive_enabled: true, verified_phone_label_enabled: false,
                  creator_subscriptions_tweet_preview_api_enabled: true,
                  responsive_web_graphql_skip_user_profile_image_extensions_enabled: false,
                  responsive_web_graphql_timeline_navigation_enabled: true
                })), {
                headers: {"Authorization": "Bearer " + bearerToken_, "x-csrf-token": ct0_, "Content-Type": "application/json"},
                credentials: "include"
              });
              if (!resp.ok) return JSON.stringify({error: "HTTP " + resp.status});
              var data = await resp.json();
              var user = data.data.user.result;
              if (user.__typename && user.__typename !== 'User' && user.user) user = user.user;
              var core = user.core || {};
              var legacy = user.legacy || {};
              var avatarObj = user.avatar || {};
              return JSON.stringify({
                screenName: core.screen_name || legacy.screen_name || "",
                name: core.name || legacy.name || "",
                avatar: (legacy.profile_image_url_https || avatarObj.image_url || "").replace('_normal', '_400x400'),
                isProtected: legacy.protected || user.privacy === "protected" || false
              });
            } catch(e) { return JSON.stringify({error: e.toString()}); }
          ''',
          arguments: {'userId_': userId, 'ct0_': ct0, 'queryId_': queryId, 'bearerToken_': bearerToken},
        );
        await _log.log('Login', 'UserByRestId result: ${jsResult?.value}');
        if (jsResult?.value != null) {
          final data = json.decode(jsResult!.value.toString()) as Map<String, dynamic>;
          if (data['error'] == null) {
            final sn = data['screenName'] as String?;
            final name = data['name'] as String?;
            final av = data['avatar'] as String?;
            if (sn != null && sn.isNotEmpty) {
              handle = '@$sn';
              displayName = (name != null && name.isNotEmpty) ? name : sn;
            }
            if (av != null && av.isNotEmpty) avatarUrl = av;
            isProtected = data['isProtected'] as bool? ?? false;
          }
        }
      } catch (e) {
        await _log.log('Login', 'UserByRestId error: $e');
      }
    }

    _updateExtractStatus(
      _gotBearerToken && _gotQueryIds && _gotNotifications && handle != '@user'
          ? '取得完了'
          : '一部取得できませんでした',
      userInfo: handle != '@user',
    );
    await _log.log('Login', 'FINAL: handle=$handle displayName=$displayName avatar=${avatarUrl ?? "null"} '
        'bearer=$_gotBearerToken queryIds=$_gotQueryIds notif=$_gotNotifications');

    final hiResAvatar = avatarUrl?.replaceFirst('_normal', '_400x400');
    final allDone = _gotBearerToken && _gotQueryIds && _gotNotifications && handle != '@user';

    if (allDone) {
      // 全て成功 → 1秒見せてから自動で閉じる
      await Future.delayed(const Duration(seconds: 1));
      await cookieManager.deleteAllCookies();
      if (mounted) {
        Navigator.of(context).pop(LoginResult(
          service: SnsService.x,
          credentials: creds,
          displayName: displayName,
          handle: handle,
          avatarUrl: hiResAvatar,
          isProtected: isProtected,
        ));
      }
    } else {
      // 一部失敗 → リトライ/続行ボタンを表示
      if (!mounted) return;
      setState(() {
        _extractStatus = '一部取得できませんでした';
        _isExtracting = false;
      });
      final retry = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('取得状況'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow('Bearer Token', _gotBearerToken),
              _buildStatusRow('queryId', _gotQueryIds),
              _buildStatusRow('ユーザー情報', handle != '@user'),
              _buildStatusRow('通知 queryId', _gotNotifications),
              const SizedBox(height: 12),
              Text(
                '取得できなかった項目があります。WebViewでページを操作してからリトライできます。',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('このまま続行'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('リトライ'),
            ),
          ],
        ),
      );

      if (retry == true && mounted) {
        // リトライ: ホームに再遷移して onLoadResource を再キャプチャ
        // 既にチェック済みの項目はリセットしない
        setState(() => _isExtracting = true);
        _capturedQueryIds.clear();
        if (_controller != null) {
          await _controller!.loadUrl(urlRequest: URLRequest(url: WebUri('https://x.com/home')));
          // ページロード+APIリクエストを待つ
          await Future.delayed(const Duration(seconds: 3));
        }
        await _extractXCredentials();
        return;
      }

      // 続行: 取得できた分で進む
      await cookieManager.deleteAllCookies();
      if (mounted) {
        Navigator.of(context).pop(LoginResult(
          service: SnsService.x,
          credentials: creds,
          displayName: displayName,
          handle: handle,
          avatarUrl: hiResAvatar,
          isProtected: isProtected,
        ));
      }
    }
  }
}


