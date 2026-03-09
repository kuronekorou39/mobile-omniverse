import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/account.dart';
import '../models/sns_service.dart';

/// セッション更新の結果
class SessionRefreshResult {
  const SessionRefreshResult({required this.credentials});
  final Object credentials;
}

/// 既存アカウントの Cookie を WebView にセットしてセッションを確認・更新する画面
class SessionRefreshScreen extends StatefulWidget {
  const SessionRefreshScreen({super.key, required this.account});

  final Account account;

  @override
  State<SessionRefreshScreen> createState() => _SessionRefreshScreenState();
}

class _SessionRefreshScreenState extends State<SessionRefreshScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _isExtracting = false;
  bool _cookiesReady = false;

  @override
  void initState() {
    super.initState();
    _prepareCookies();
  }

  /// 既存アカウントの Cookie を WebView に設定
  Future<void> _prepareCookies() async {
    final cookieManager = CookieManager.instance();
    // まず全 Cookie をクリア（他アカウントの Cookie が残っていると干渉する）
    await cookieManager.deleteAllCookies();
    await InAppWebViewController.clearAllCache();

    if (widget.account.service == SnsService.x) {
      final creds = widget.account.xCredentials;
      // allCookies をパースして個別にセット
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
        debugPrint('[SessionRefresh] Set ${pairs.length} cookies for x.com');
      } else {
        // allCookies がない場合は auth_token と ct0 だけセット
        await cookieManager.setCookie(
          url: WebUri('https://x.com'),
          name: 'auth_token',
          value: creds.authToken,
          domain: '.x.com',
          path: '/',
        );
        await cookieManager.setCookie(
          url: WebUri('https://x.com'),
          name: 'ct0',
          value: creds.ct0,
          domain: '.x.com',
          path: '/',
        );
        debugPrint('[SessionRefresh] Set auth_token + ct0 for x.com');
      }
    }
    // Bluesky の場合は localStorage ベースなので Cookie セットは不要

    if (mounted) {
      setState(() => _cookiesReady = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.account.service;

    return Scaffold(
      appBar: AppBar(
        title: Text('${service.label} セッション更新'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isExtracting ? null : _onDonePressed,
            icon: const Icon(Icons.check),
            label: const Text('更新'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_progress < 1.0) LinearProgressIndicator(value: _progress),
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
                child: !_cookiesReady
                    ? const Center(child: CircularProgressIndicator())
                    : InAppWebView(
                        initialUrlRequest: URLRequest(
                          url: WebUri(service.homeUrl),
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
                        },
                        onProgressChanged: (_, progress) {
                          setState(() => _progress = progress / 100);
                        },
                        onLoadStop: (controller, url) {
                          debugPrint('[SessionRefresh] onLoadStop: $url');
                        },
                      ),
              ),
            ],
          ),
          if (_isExtracting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Card(
                  margin: EdgeInsets.all(32),
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 24),
                        Text(
                          '認証情報を更新中...',
                          style: TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
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

  Future<void> _onDonePressed() async {
    setState(() => _isExtracting = true);

    try {
      switch (widget.account.service) {
        case SnsService.x:
          await _extractXCredentials();
        case SnsService.bluesky:
          await _extractBlueskyCredentials();
      }
    } catch (e) {
      debugPrint('[SessionRefresh] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('認証情報の更新に失敗しました: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _isExtracting = false);
    }
  }

  Future<void> _extractXCredentials() async {
    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(
      url: WebUri('https://x.com'),
    );

    String? authToken;
    String? ct0;
    final cookieParts = <String>[];

    for (final cookie in cookies) {
      cookieParts.add('${cookie.name}=${cookie.value}');
      if (cookie.name == 'auth_token') {
        authToken = cookie.value.toString();
      } else if (cookie.name == 'ct0') {
        ct0 = cookie.value.toString();
      }
    }

    final allCookies = cookieParts.join('; ');
    debugPrint('[SessionRefresh] X cookies: '
        'auth_token=${authToken != null}, ct0=${ct0 != null}, total=${cookies.length}');

    if (authToken == null || ct0 == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cookie が取得できませんでした。ログインし直してください。')),
        );
      }
      return;
    }

    final newCreds = XCredentials(
      authToken: authToken,
      ct0: ct0,
      allCookies: allCookies,
    );

    // Cookie クリア
    await cookieManager.deleteAllCookies();

    if (mounted) {
      Navigator.of(context).pop(SessionRefreshResult(credentials: newCreds));
    }
  }

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
          const SnackBar(content: Text('セッション情報が見つかりませんでした')),
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

    final newCreds = BlueskyCredentials(
      accessJwt: session['accessJwt'] as String,
      refreshJwt: session['refreshJwt'] as String,
      did: session['did'] as String,
      handle: session['handle'] as String,
    );

    await CookieManager.instance().deleteAllCookies();

    if (mounted) {
      Navigator.of(context).pop(SessionRefreshResult(credentials: newCreds));
    }
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
}
