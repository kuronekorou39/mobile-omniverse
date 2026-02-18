import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/sns_service.dart';

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
      body: Column(
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
            child: InAppWebView(
              // 旧版と同じ: home URL を開く
              initialUrlRequest: URLRequest(
                url: WebUri(widget.service.homeUrl),
              ),
              // 旧版と完全に同じ設定
              initialSettings: InAppWebViewSettings(
                userAgent:
                    'Mozilla/5.0 (Linux; Android 14; Pixel 8) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/120.0.0.0 Mobile Safari/537.36',
                javaScriptEnabled: true,
                domStorageEnabled: true,
              ),
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
              onLoadStop: (_, url) {
                debugPrint('[LoginWebView] onLoadStop: $url');
              },
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
    await CookieManager.instance().deleteCookies(
      url: WebUri('https://bsky.app'),
    );

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

    for (final cookie in cookies) {
      if (cookie.name == 'auth_token') {
        authToken = cookie.value.toString();
      } else if (cookie.name == 'ct0') {
        ct0 = cookie.value.toString();
      } else if (cookie.name == 'twid') {
        twid = cookie.value.toString();
      }
    }

    debugPrint('[LoginWebView] X cookies: '
        'auth_token=${authToken != null}, ct0=${ct0 != null}');

    if (authToken == null || ct0 == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('X にログインしてから「完了」を押してください')),
        );
      }
      return;
    }

    final creds = XCredentials(authToken: authToken, ct0: ct0);

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
              var queryId = "tD8zKvQzwY3kdx5yz6YmOw";
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

    debugPrint('[LoginWebView] X login: $handle ($displayName)');

    final loginResult = LoginResult(
      service: SnsService.x,
      credentials: creds,
      displayName: displayName,
      handle: handle,
      avatarUrl: avatarUrl,
    );

    // auth Cookie のみクリア (次回ログイン用にセッション Cookie は残す)
    for (final name in ['auth_token', 'ct0']) {
      await cookieManager.deleteCookie(
        url: WebUri('https://x.com'),
        name: name,
      );
    }

    if (mounted) Navigator.of(context).pop(loginResult);
  }
}
