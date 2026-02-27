import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';

/// X の GraphQL queryId を管理するサービス
/// JS バンドルから最新の queryId を取得してキャッシュする
/// queryId はアカウントごとに異なる場合がある (X の A/B テスト等)
class XQueryIdService {
  XQueryIdService._();
  static final instance = XQueryIdService._();

  @visibleForTesting
  http.Client? httpClientOverride;

  static const _prefsKey = 'x_query_ids';
  static const _perAccountPrefsKey = 'x_query_ids_per_account';
  static const _lastRefreshKey = 'x_query_ids_last_refresh';
  static const _minRefreshInterval = Duration(hours: 1);

  /// デフォルトの queryId (フォールバック用)
  static const _defaults = <String, String>{
    'HomeLatestTimeline': 'BKB7oi212Fi7kQtCBGE4zA',
    'TweetDetail': 'nBS-WpgA6ZG0CyNHD517JQ',
    'FavoriteTweet': 'lI07N6Otwv1PhnEgXILM7A',
    'UnfavoriteTweet': 'ZYKSe-w7KEslx3JhSIk5LA',
    'CreateRetweet': 'ojPdsZsimiJrUGLR1sjUtA',
    'DeleteRetweet': 'iQtK4dl5hBmXewYZuEOKVw',
    'UserByRestId': 'tD8zKvQzwY3kdx5yz6YmOw',
    'UserByScreenName': 'xmU_MTpREJBz1I14LU744A',
    'UserTweets': 'E3opETHurmVJflFsUBVuUQ',
    'UserMedia': 'dexO_2tohK86JDlXOGVk-w',
    'CreateTweet': 'a1p9RWpkYKBjWv_I3WzS-A',
  };

  /// グローバルキャッシュ (旧形式・マイグレーション用)
  final Map<String, String> _cached = {};
  DateTime? _lastRefresh;

  /// アカウントごとの queryId キャッシュ
  final Map<String, Map<String, String>> _perAccount = {};
  final Map<String, DateTime> _perAccountLastRefresh = {};

  /// アカウント識別キー (authToken のハッシュ)
  static String _accountKey(XCredentials creds) =>
      creds.authToken.hashCode.toRadixString(16);

  /// 初期化: SharedPreferences からキャッシュをロード
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // 旧形式のグローバルキャッシュ読み込み (マイグレーション互換)
    final stored = prefs.getString(_prefsKey);
    if (stored != null) {
      try {
        final map = json.decode(stored) as Map<String, dynamic>;
        for (final entry in map.entries) {
          _cached[entry.key] = entry.value as String;
        }
        debugPrint('[XQueryId] Loaded ${_cached.length} global cached queryIds');
      } catch (e) {
        debugPrint('[XQueryId] Error loading global cache: $e');
      }
    }

    // アカウント別キャッシュ読み込み
    final perAccountRaw = prefs.getString(_perAccountPrefsKey);
    if (perAccountRaw != null) {
      try {
        final outer = json.decode(perAccountRaw) as Map<String, dynamic>;
        for (final entry in outer.entries) {
          final inner = entry.value as Map<String, dynamic>;
          _perAccount[entry.key] = inner.map((k, v) => MapEntry(k, v as String));
        }
        debugPrint('[XQueryId] Loaded per-account queryIds for ${_perAccount.length} accounts');
      } catch (e) {
        debugPrint('[XQueryId] Error loading per-account cache: $e');
      }
    }

    final lastRefreshMs = prefs.getInt(_lastRefreshKey);
    if (lastRefreshMs != null) {
      _lastRefresh = DateTime.fromMillisecondsSinceEpoch(lastRefreshMs);
    }
  }

  /// operationName に対応する queryId を取得
  /// [creds] を指定するとアカウント固有の値を優先、なければデフォルト
  String getQueryId(String operationName, {XCredentials? creds}) {
    // 1. アカウント別キャッシュ
    if (creds != null) {
      final key = _accountKey(creds);
      final acctCache = _perAccount[key];
      if (acctCache != null && acctCache.containsKey(operationName)) {
        return acctCache[operationName]!;
      }
    }
    // 2. デフォルト値 (グローバルキャッシュは使わない — 別アカウントの汚染を防ぐ)
    return _defaults[operationName] ?? '';
  }

  /// x.com の JS バンドルから queryId を取得して更新
  /// [creds] は Cookie 認証に使用、結果はそのアカウント専用に保存
  /// Returns: 更新された operationName の数
  Future<int> refreshQueryIds(XCredentials? creds) async {
    // アカウント別レート制限チェック
    if (creds != null) {
      final key = _accountKey(creds);
      final last = _perAccountLastRefresh[key];
      if (last != null && DateTime.now().difference(last) < _minRefreshInterval) {
        debugPrint('[XQueryId] Skipping refresh for account $key (rate limited)');
        return 0;
      }
    } else if (_lastRefresh != null) {
      final elapsed = DateTime.now().difference(_lastRefresh!);
      if (elapsed < _minRefreshInterval) {
        debugPrint('[XQueryId] Skipping refresh (last: ${elapsed.inMinutes}m ago)');
        return 0;
      }
    }

    debugPrint('[XQueryId] Starting queryId refresh...');

    try {
      // 1. x.com の HTML を取得
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      };
      if (creds != null) {
        headers['Cookie'] = creds.cookieHeader;
      }

      final client = httpClientOverride ?? http.Client();
      final htmlResponse = await client.get(
        Uri.parse('https://x.com/home'),
        headers: headers,
      );

      if (htmlResponse.statusCode != 200) {
        debugPrint('[XQueryId] HTML fetch failed: ${htmlResponse.statusCode}');
        return 0;
      }

      // 2. <script src="..."> から JS バンドル URL を抽出
      final scriptPattern = RegExp(
        r'<script[^>]+src="(https://abs\.twimg\.com/responsive-web/client-web[^"]*\.js)"',
      );
      final matches = scriptPattern.allMatches(htmlResponse.body);
      final bundleUrls = matches.map((m) => m.group(1)!).toList();

      debugPrint('[XQueryId] Found ${bundleUrls.length} JS bundle URLs');

      if (bundleUrls.isEmpty) {
        debugPrint('[XQueryId] No JS bundles found');
        return 0;
      }

      // 3. 各バンドルから queryId を抽出
      final found = <String, String>{};
      final targetOps = _defaults.keys.toSet();

      for (final url in bundleUrls) {
        if (found.length >= targetOps.length) break;

        try {
          final jsResponse = await client.get(
            Uri.parse(url),
            headers: {
              'User-Agent': headers['User-Agent']!,
            },
          );

          if (jsResponse.statusCode != 200) continue;

          // queryId:"xxx",operationName:"yyy" パターン
          final pattern = RegExp(
            r'queryId\s*:\s*"([A-Za-z0-9_-]+)"\s*,\s*operationName\s*:\s*"([A-Za-z0-9_]+)"',
          );
          for (final match in pattern.allMatches(jsResponse.body)) {
            final queryId = match.group(1)!;
            final opName = match.group(2)!;
            if (targetOps.contains(opName)) {
              found[opName] = queryId;
            }
          }

          // operationName:"yyy",...,queryId:"xxx" の逆順パターンも探す
          final reversePattern = RegExp(
            r'operationName\s*:\s*"([A-Za-z0-9_]+)"[^}]*?queryId\s*:\s*"([A-Za-z0-9_-]+)"',
          );
          for (final match in reversePattern.allMatches(jsResponse.body)) {
            final opName = match.group(1)!;
            final queryId = match.group(2)!;
            if (targetOps.contains(opName) && !found.containsKey(opName)) {
              found[opName] = queryId;
            }
          }
        } catch (e) {
          debugPrint('[XQueryId] Error fetching bundle $url: $e');
        }
      }

      debugPrint('[XQueryId] Found ${found.length} queryIds: ${found.keys.toList()}');

      if (found.isNotEmpty) {
        if (creds != null) {
          // アカウント専用に保存 (他アカウントに影響しない)
          final key = _accountKey(creds);
          _perAccount[key] ??= {};
          _perAccount[key]!.addAll(found);
          debugPrint('[XQueryId] Stored queryIds for account $key');
        } else {
          _cached.addAll(found);
        }
        await _saveToPrefs();
      }

      // アカウント別のレート制限を記録
      if (creds != null) {
        _perAccountLastRefresh[_accountKey(creds)] = DateTime.now();
      } else {
        _lastRefresh = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_lastRefreshKey, _lastRefresh!.millisecondsSinceEpoch);
      }

      return found.length;
    } catch (e) {
      debugPrint('[XQueryId] Refresh error: $e');
      return 0;
    }
  }

  /// キャッシュを SharedPreferences に保存
  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // グローバルキャッシュ
    await prefs.setString(_prefsKey, json.encode(_cached));
    // アカウント別キャッシュ
    final perAccountJson = _perAccount.map((k, v) => MapEntry(k, v));
    await prefs.setString(_perAccountPrefsKey, json.encode(perAccountJson));
    debugPrint('[XQueryId] Saved queryIds to prefs (${_perAccount.length} accounts)');
  }

  /// 強制リフレッシュ (レート制限を無視)
  Future<int> forceRefresh(XCredentials? creds) async {
    if (creds != null) {
      _perAccountLastRefresh.remove(_accountKey(creds));
    } else {
      _lastRefresh = null;
    }
    return refreshQueryIds(creds);
  }

  /// キャッシュを全消去してデフォルト値に戻す
  Future<void> clearCache() async {
    _cached.clear();
    _perAccount.clear();
    _perAccountLastRefresh.clear();
    _lastRefresh = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await prefs.remove(_perAccountPrefsKey);
    await prefs.remove(_lastRefreshKey);
    debugPrint('[XQueryId] Cache cleared, using defaults');
  }

  /// 現在のキャッシュ状態を取得 (デバッグ用)
  Map<String, String> currentIds({XCredentials? creds}) => Map.unmodifiable({
        for (final op in _defaults.keys) op: getQueryId(op, creds: creds),
      });

  /// 最終更新日時
  DateTime? lastRefreshTime({XCredentials? creds}) {
    if (creds != null) {
      return _perAccountLastRefresh[_accountKey(creds)];
    }
    return _lastRefresh;
  }
}
