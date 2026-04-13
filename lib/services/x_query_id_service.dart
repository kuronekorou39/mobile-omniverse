import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../utils/image_headers.dart';
import 'x_endpoints.dart';

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

  /// 管理対象のオペレーション名一覧（JSバンドルからこれらのqueryIdを取得する）
  static const _targetOperations = <String>{
    'HomeLatestTimeline',
    'TweetDetail',
    'FavoriteTweet',
    'UnfavoriteTweet',
    'CreateRetweet',
    'DeleteRetweet',
    'UserByRestId',
    'UserByScreenName',
    'UserTweets',
    'UserMedia',
    'CreateTweet',
    'NotificationsTimeline',
  };

  /// グローバルキャッシュ (旧形式・マイグレーション用)
  final Map<String, String> _cached = {};
  DateTime? _lastRefresh;

  /// アカウントごとの queryId キャッシュ
  final Map<String, Map<String, String>> _perAccount = {};
  final Map<String, DateTime> _perAccountLastRefresh = {};

  /// アカウント識別キー
  static String _accountKey(XCredentials creds) => creds.authToken;

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
      } catch (_) {}
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
      } catch (_) {}
    }

    final lastRefreshMs = prefs.getInt(_lastRefreshKey);
    if (lastRefreshMs != null) {
      _lastRefresh = DateTime.fromMillisecondsSinceEpoch(lastRefreshMs);
    }

    // キャッシュが空でもここでは何もしない
    // ログイン時やAPI呼び出し時にcreds付きで取得される
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
    // 2. グローバルキャッシュ（JSバンドルから取得済みの値）
    if (_cached.containsKey(operationName)) {
      return _cached[operationName]!;
    }
    // 未取得
    return '';
  }

  /// x.com の JS バンドルから queryId を取得して更新
  /// [creds] は Cookie 認証に使用、結果はそのアカウント専用に保存
  /// [onlyUpdate] を指定すると、そのオペレーションのみキャッシュ更新する
  /// Returns: 更新された operationName の数
  Future<int> refreshQueryIds(XCredentials? creds, {Set<String>? onlyUpdate}) async {
    // アカウント別レート制限チェック
    if (creds != null) {
      final key = _accountKey(creds);
      final last = _perAccountLastRefresh[key];
      if (last != null && DateTime.now().difference(last) < _minRefreshInterval) {
        return 0;
      }
    } else if (_lastRefresh != null) {
      if (DateTime.now().difference(_lastRefresh!) < _minRefreshInterval) {
        return 0;
      }
    }

    try {
      // 1. x.com の HTML を取得
      final headers = <String, String>{
        'User-Agent': kUserAgent,
      };
      if (creds != null) {
        headers['Cookie'] = creds.cookieHeader;
      }

      final client = httpClientOverride ?? http.Client();
      final htmlResponse = await client.get(
        Uri.parse(XEndpoints.home),
        headers: headers,
      );

      if (htmlResponse.statusCode != 200) return 0;

      // 2. <script src="..."> から JS バンドル URL を抽出
      final scriptPattern = RegExp(
        r'<script[^>]+src="(https://abs\.twimg\.com/responsive-web/client-web[^"]*\.js)"',
      );
      final scriptPattern2 = RegExp(
        r'<script[^>]+src="(https://abs\.twimg\.com/responsive-web/[^"]*(?:api|main|vendor)[^"]*\.js)"',
      );
      final bundleUrls = <String>{};
      for (final m in scriptPattern.allMatches(htmlResponse.body)) {
        bundleUrls.add(m.group(1)!);
      }
      for (final m in scriptPattern2.allMatches(htmlResponse.body)) {
        bundleUrls.add(m.group(1)!);
      }

      if (bundleUrls.isEmpty) return 0;

      // 3. 各バンドルから queryId を抽出
      final found = <String, String>{};
      final targetOps = _targetOperations;

      for (final url in bundleUrls.toList()) {
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

          // operationName:"yyy",...,queryId:"xxx" の逆順パターン
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

          // exports={queryId:"xxx",operationName:"yyy"} パターン (minified)
          final exportPattern = RegExp(
            r'exports\s*=\s*\{[^}]*?queryId\s*:\s*"([A-Za-z0-9_-]+)"[^}]*?operationName\s*:\s*"([A-Za-z0-9_]+)"',
          );
          for (final match in exportPattern.allMatches(jsResponse.body)) {
            final queryId = match.group(1)!;
            final opName = match.group(2)!;
            if (targetOps.contains(opName) && !found.containsKey(opName)) {
              found[opName] = queryId;
            }
          }
        } catch (_) {}
      }

      if (found.isNotEmpty) {
        final toStore = onlyUpdate != null
            ? Map.fromEntries(found.entries.where((e) => onlyUpdate.contains(e.key)))
            : found;

        if (toStore.isNotEmpty) {
          // グローバルキャッシュに常に保存（全アカウントで共有）
          _cached.addAll(toStore);
          if (creds != null) {
            final key = _accountKey(creds);
            _perAccount[key] ??= {};
            _perAccount[key]!.addAll(toStore);
          }
          await _saveToPrefs();
        }
      }

      // アカウント別のレート制限を記録
      if (creds != null) {
        _perAccountLastRefresh[_accountKey(creds)] = DateTime.now();
      } else {
        _lastRefresh = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_lastRefreshKey, _lastRefresh!.millisecondsSinceEpoch);
      }

      debugPrint('[XQueryId] Refreshed ${found.length} queryIds');
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
  }

  /// 強制リフレッシュ (レート制限を無視)
  /// [onlyUpdate] を指定すると、そのオペレーションの queryId のみ更新する
  /// (他のオペレーション、特に HomeLatestTimeline を壊さない)
  Future<int> forceRefresh(XCredentials? creds, {Set<String>? onlyUpdate}) async {
    if (creds != null) {
      _perAccountLastRefresh.remove(_accountKey(creds));
    } else {
      _lastRefresh = null;
    }
    return refreshQueryIds(creds, onlyUpdate: onlyUpdate);
  }

  /// WebView 等で取得した queryId をアカウント別 + グローバルキャッシュに保存
  Future<void> updateQueryIds(XCredentials creds, Map<String, String> ids) async {
    final key = _accountKey(creds);
    _perAccount[key] ??= {};
    _perAccount[key]!.addAll(ids);
    // グローバルキャッシュにも保存（他アカウントから参照可能にする）
    _cached.addAll(ids);
    await _saveToPrefs();
    debugPrint('[XQueryId] Updated ${ids.length} queryIds for account: ${ids.keys.join(', ')}');
  }

  /// 特定オペレーションのキャッシュを消去してデフォルト値に戻す
  /// (リフレッシュで取得した queryId が不正なレスポンスを返す場合に使用)
  Future<void> revertToDefault(XCredentials? creds, String operationName) async {
    if (creds != null) {
      final key = _accountKey(creds);
      _perAccount[key]?.remove(operationName);
    } else {
      _cached.remove(operationName);
    }
    await _saveToPrefs();
    debugPrint('[XQueryId] Reverted $operationName (cache cleared)');
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
  }

  /// 現在のキャッシュ状態を取得 (デバッグ用)
  Map<String, String> currentIds({XCredentials? creds}) => Map.unmodifiable({
        for (final op in _targetOperations) op: getQueryId(op, creds: creds),
      });

  /// 最終更新日時
  DateTime? lastRefreshTime({XCredentials? creds}) {
    if (creds != null) {
      return _perAccountLastRefresh[_accountKey(creds)];
    }
    return _lastRefresh;
  }
}
