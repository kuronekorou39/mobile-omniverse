import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';

/// X の GraphQL queryId を管理するサービス
/// JS バンドルから最新の queryId を取得してキャッシュする
class XQueryIdService {
  XQueryIdService._();
  static final instance = XQueryIdService._();

  static const _prefsKey = 'x_query_ids';
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
  };

  final Map<String, String> _cached = {};
  DateTime? _lastRefresh;

  /// 初期化: SharedPreferences からキャッシュをロード
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null) {
      try {
        final map = json.decode(stored) as Map<String, dynamic>;
        for (final entry in map.entries) {
          _cached[entry.key] = entry.value as String;
        }
        debugPrint('[XQueryId] Loaded ${_cached.length} cached queryIds');
      } catch (e) {
        debugPrint('[XQueryId] Error loading cache: $e');
      }
    }
    final lastRefreshMs = prefs.getInt(_lastRefreshKey);
    if (lastRefreshMs != null) {
      _lastRefresh = DateTime.fromMillisecondsSinceEpoch(lastRefreshMs);
    }
  }

  /// operationName に対応する queryId を取得
  /// キャッシュにあればそれを、なければデフォルト値を返す
  String getQueryId(String operationName) {
    return _cached[operationName] ?? _defaults[operationName] ?? '';
  }

  /// x.com の JS バンドルから queryId を取得して更新
  /// [creds] は Cookie 認証に使用（null の場合は Cookie なしで試行）
  /// Returns: 更新された operationName の数
  Future<int> refreshQueryIds(XCredentials? creds) async {
    // レート制限チェック
    if (_lastRefresh != null) {
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

      final htmlResponse = await http.get(
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
          final jsResponse = await http.get(
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
        _cached.addAll(found);
        await _saveToPrefs();
      }

      _lastRefresh = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastRefreshKey, _lastRefresh!.millisecondsSinceEpoch);

      return found.length;
    } catch (e) {
      debugPrint('[XQueryId] Refresh error: $e');
      return 0;
    }
  }

  /// キャッシュを SharedPreferences に保存
  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, json.encode(_cached));
    debugPrint('[XQueryId] Saved ${_cached.length} queryIds to prefs');
  }

  /// 強制リフレッシュ (レート制限を無視)
  Future<int> forceRefresh(XCredentials? creds) async {
    _lastRefresh = null;
    return refreshQueryIds(creds);
  }

  /// キャッシュを全消去してデフォルト値に戻す
  Future<void> clearCache() async {
    _cached.clear();
    _lastRefresh = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await prefs.remove(_lastRefreshKey);
    debugPrint('[XQueryId] Cache cleared, using defaults');
  }

  /// 現在のキャッシュ状態を取得 (デバッグ用)
  Map<String, String> get currentIds => Map.unmodifiable({
        for (final op in _defaults.keys) op: getQueryId(op),
      });

  /// 最終更新日時
  DateTime? get lastRefreshTime => _lastRefresh;
}
