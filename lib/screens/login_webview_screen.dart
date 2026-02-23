import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/sns_service.dart';
import '../services/x_query_id_service.dart';

/// ログイン完了時に返す認証情報
class LoginResult {
  const LoginResult({
    required this.service,
    required this.credentials,
    required this.displayName,
    required this.handle,
    this.avatarUrl,
  });

  final SnsService service;
  final Object credentials;
  final String displayName;
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

/// X の fetch をインターセプトしてユーザー情報をキャプチャするスクリプト
const _xFetchInterceptorScript = '''
(function() {
  window.__xCapturedUser = null;
  var _origFetch = window.fetch;
  window.fetch = function() {
    var url = '';
    if (typeof arguments[0] === 'string') {
      url = arguments[0];
    } else if (arguments[0] && arguments[0].url) {
      url = arguments[0].url;
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
              window.__xCapturedUser.avatar = legacy.profile_image_url_https;
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
                window.__xCapturedUser.avatar = legacy.profile_image_url_https;
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
  bool _cookiesCleared = false;

  static const _waitingMessages = [
    'ちょっとまってね...',
    'もうすぐだよ！',
    '処理中、、',
    'おそいね〜',
    'がんばってます...',
    'サーバーさんおきて！',
    'コーヒーでも飲んでて',
    '認証情報を取得中...',
    'あとちょっと...',
    'ネットワーク通信中...',
  ];

  @override
  void initState() {
    super.initState();
    _clearCookiesBeforeLogin();
  }

  /// ログイン前に該当ドメインの Cookie をクリア（他アカウントと干渉しないように）
  Future<void> _clearCookiesBeforeLogin() async {
    final cookieManager = CookieManager.instance();
    // 全 Cookie を削除（ドメイン指定だとサブドメイン Cookie が残る場合がある）
    await cookieManager.deleteAllCookies();
    // WebView のキャッシュ・ストレージもクリア
    await InAppWebViewController.clearAllCache();
    debugPrint('[LoginWebView] All cookies and cache cleared');
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
          // ナビゲーションバー (旧版と同じ)
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
            ],
          ),
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
                    'Chrome/120.0.0.0 Mobile Safari/537.36',
                javaScriptEnabled: true,
                domStorageEnabled: true,
                // Google OAuth などの外部ドメインリダイレクトを許可
                useShouldOverrideUrlLoading: true,
                // 3rd party cookies (Google OAuth に必要)
                thirdPartyCookiesEnabled: true,
              ),
              // Google OAuth リダイレクト等を適切に処理
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final url = navigationAction.request.url?.toString() ?? '';
                // Google OAuth, Apple ID など外部認証プロバイダのドメインは許可
                final allowedDomains = [
                  'accounts.google.com',
                  'accounts.youtube.com',
                  'appleid.apple.com',
                  'x.com',
                  'twitter.com',
                  'api.twitter.com',
                  'bsky.app',
                  'bsky.social',
                ];
                final uri = Uri.tryParse(url);
                if (uri != null) {
                  final host = uri.host;
                  for (final domain in allowedDomains) {
                    if (host == domain || host.endsWith('.$domain')) {
                      return NavigationActionPolicy.ALLOW;
                    }
                  }
                }
                // その他の URL も基本的に許可（リダイレクトチェーンを壊さない）
                return NavigationActionPolicy.ALLOW;
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
              onLoadStop: (controller, url) {
                debugPrint('[LoginWebView] onLoadStop: $url');
                // Google OAuth 完了後に元のサイトに戻った場合を検出
                final urlStr = url?.toString() ?? '';
                if (urlStr.contains(widget.service.domain)) {
                  debugPrint('[LoginWebView] Returned to ${widget.service.domain}');
                }
                // X の場合: fetch interceptor を再注入
                // (Google OAuth リダイレクト後にスクリプトが消えることがある)
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
          // 待機演出オーバーレイ
          if (_isExtracting)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        _WaitingMessageAnimation(
                          messages: _waitingMessages,
                        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('認証情報の取得に失敗しました: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Bluesky にログインしてから「完了」を押してください')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('セッション情報が見つかりませんでした')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('X にログインしてから「完了」を押してください')),
        );
      }
      return;
    }

    final creds = XCredentials(authToken: authToken, ct0: ct0, allCookies: allCookies);

    // WebView 内の fetch でユーザー情報取得（全 Cookie が自動送信される）
    String displayName = 'X User';
    String handle = '@user';
    String? avatarUrl;

    // twid の形式: "u%3D1234567890" → userId = "1234567890"
    String? userId;
    if (twid != null) {
      final decoded = Uri.decodeComponent(twid);
      final match = RegExp(r'u=(\d+)').firstMatch(decoded);
      userId = match?.group(1);
      debugPrint('[LoginWebView] X twid=$twid → userId=$userId');
    }

    if (userId != null && _controller != null) {
      try {
        // WebView 内で fetch を実行（ブラウザの全 Cookie が使われる）
        final jsResult = await _controller!.callAsyncJavaScript(
          functionBody: '''
            try {
              var userId = userId_;
              var ct0 = ct0_;
              var queryId = "${XQueryIdService.instance.getQueryId('UserByRestId')}";
              var variables = JSON.stringify({userId: userId, withSafetyModeUserFields: true});
              var features = JSON.stringify({
                hidden_profile_subscriptions_enabled: true,
                rweb_tipjar_consumption_enabled: true,
                responsive_web_graphql_exclude_directive_enabled: true,
                verified_phone_label_enabled: false,
                highlights_tweets_tab_ui_enabled: true,
                responsive_web_twitter_article_notes_tab_enabled: true,
                subscriptions_feature_can_gift_premium: true,
                creator_subscriptions_tweet_preview_api_enabled: true,
                responsive_web_graphql_skip_user_profile_image_extensions_enabled: false,
                responsive_web_graphql_timeline_navigation_enabled: true
              });
              var url = "https://x.com/i/api/graphql/" + queryId + "/UserByRestId"
                + "?variables=" + encodeURIComponent(variables)
                + "&features=" + encodeURIComponent(features);

              var resp = await fetch(url, {
                headers: {
                  "Authorization": "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA",
                  "x-csrf-token": ct0,
                  "x-twitter-active-user": "yes",
                  "x-twitter-client-language": "ja",
                  "Content-Type": "application/json"
                },
                credentials: "include"
              });

              if (!resp.ok) {
                return JSON.stringify({error: "HTTP " + resp.status});
              }

              var data = await resp.json();
              var user = data.data.user.result;
              var legacy = user.legacy || {};
              return JSON.stringify({
                screenName: legacy.screen_name || "",
                name: legacy.name || "",
                avatar: legacy.profile_image_url_https || ""
              });
            } catch(e) {
              return JSON.stringify({error: e.toString()});
            }
          ''',
          arguments: {'userId_': userId, 'ct0_': ct0},
        );

        debugPrint('[LoginWebView] UserByRestId JS result: ${jsResult?.value}');

        if (jsResult?.value != null) {
          final resultStr = jsResult!.value.toString();
          final data = json.decode(resultStr) as Map<String, dynamic>;
          if (data['error'] == null) {
            final sn = data['screenName'] as String?;
            final name = data['name'] as String?;
            final av = data['avatar'] as String?;
            if (sn != null && sn.isNotEmpty) {
              handle = '@$sn';
              displayName = (name != null && name.isNotEmpty) ? name : sn;
            }
            if (av != null && av.isNotEmpty) avatarUrl = av;
            debugPrint('[LoginWebView] X user from WebView: $handle ($displayName)');
          } else {
            debugPrint('[LoginWebView] UserByRestId error: ${data['error']}');
          }
        }
      } catch (e) {
        debugPrint('[LoginWebView] Error getting X user via WebView fetch: $e');
      }
    } else {
      debugPrint('[LoginWebView] No twid/controller, cannot get user info');
    }

    // UserByRestId が失敗した場合、fetch interceptor で捕捉したデータにフォールバック
    if (handle == '@user' && _controller != null) {
      try {
        final captured = await _controller!.evaluateJavascript(
          source: 'JSON.stringify(window.__xCapturedUser)',
        );
        if (captured != null && captured != 'null') {
          final data = json.decode(captured.toString()) as Map<String, dynamic>;
          final sn = data['screenName'] as String?;
          final name = data['name'] as String?;
          final av = data['avatar'] as String?;
          if (sn != null && sn.isNotEmpty) {
            handle = '@$sn';
            displayName = (name != null && name.isNotEmpty) ? name : sn;
          }
          if (av != null && av.isNotEmpty) avatarUrl = av;
          debugPrint('[LoginWebView] X user from interceptor: $handle ($displayName)');
        }
      } catch (e) {
        debugPrint('[LoginWebView] Error reading interceptor data: $e');
      }
    }

    debugPrint('[LoginWebView] X login: $handle ($displayName)');

    final loginResult = LoginResult(
      service: SnsService.x,
      credentials: creds,
      displayName: displayName,
      handle: handle,
      avatarUrl: avatarUrl,
    );

    // 全 Cookie をクリア（次回ログイン時に別アカウントと干渉しないように）
    await cookieManager.deleteAllCookies();

    if (mounted) Navigator.of(context).pop(loginResult);
  }
}

/// ランダムな待機メッセージを切り替えて表示するウィジェット
class _WaitingMessageAnimation extends StatefulWidget {
  const _WaitingMessageAnimation({required this.messages});

  final List<String> messages;

  @override
  State<_WaitingMessageAnimation> createState() =>
      _WaitingMessageAnimationState();
}

class _WaitingMessageAnimationState extends State<_WaitingMessageAnimation> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = DateTime.now().millisecond % widget.messages.length;
    _startRotation();
  }

  void _startRotation() {
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.messages.length;
      });
      _startRotation();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: Text(
        widget.messages[_currentIndex],
        key: ValueKey(_currentIndex),
        style: const TextStyle(fontSize: 16),
        textAlign: TextAlign.center,
      ),
    );
  }
}
