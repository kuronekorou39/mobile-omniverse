import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/notification_item.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../utils/image_headers.dart';
import 'debug_log_service.dart';
import 'x_bearer_token_service.dart';
import 'x_endpoints.dart';
import 'x_features.dart';
import 'x_query_id_service.dart';

/// HTML参照文字をデコード（&amp; &lt; &gt; &quot; &#39; &#数値;）
String _decodeHtmlEntities(String text) {
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)));
}

class XApiService {
  XApiService._();
  static final instance = XApiService._();

  @visibleForTesting
  http.Client? httpClientOverride;

  String get _bearerToken => XBearerTokenService.instance.token;

  /// Bearer Token が未取得の場合にCookie付きで取得を試みる。
  Future<void> _ensureBearerToken(XCredentials creds) async {
    if (!XBearerTokenService.instance.hasToken) {
      await XBearerTokenService.instance.refresh(cookie: creds.cookieHeader, force: true);
    }
  }

  /// 最新の ct0 をアカウント別に追跡 (APIレスポンスの Set-Cookie で更新)
  final Map<String, String> _latestCt0 = {};

  /// レスポンスの Set-Cookie から ct0 を抽出して更新
  void _updateCt0FromResponse(XCredentials creds, http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null) return;
    final match = RegExp(r'ct0=([^;]+)').firstMatch(setCookie);
    if (match != null) {
      final newCt0 = match.group(1)!;
      if (_latestCt0[creds.authToken] != newCt0) {
        _latestCt0[creds.authToken] = newCt0;
      }
    }
  }

  /// 429 レートリミット対応: retry-after を尊重した exponential backoff
  Future<http.Response> _withRateLimitRetry(
    Future<http.Response> Function() request, {
    int maxRetries = 2,
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      final response = await request();
      if (response.statusCode != 429 || attempt == maxRetries) {
        return response;
      }
      final retryAfter = response.headers['retry-after'];
      final seconds = retryAfter != null
          ? (int.tryParse(retryAfter) ?? (2 << attempt))
          : (2 << attempt);
      final wait = Duration(seconds: seconds.clamp(1, 60));
      debugPrint('[XApi] 429 Rate limited, retry in ${wait.inSeconds}s (${attempt + 1}/$maxRetries)');
      await Future.delayed(wait);
    }
    throw StateError('Unreachable');
  }

  late final http.Client _sharedClient = http.Client();
  http.Client get _client => httpClientOverride ?? _sharedClient;

  static final _random = Random.secure();
  String _generateTransactionId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// 送信する Cookie 文字列から ct0 を抽出
  String _ct0FromCookie(String cookie) {
    final m = RegExp(r'(?:^|;\s*)ct0=([^;]+)').firstMatch(cookie);
    return m?.group(1) ?? '';
  }

  Map<String, String> _buildHeaders(XCredentials creds,
          {bool form = false, String? cookieOverride}) {
    final cookie = cookieOverride ?? creds.cookieHeader;
    // x-csrf-token は必ず送信する Cookie 内の ct0 と一致させる
    final ct0 = _ct0FromCookie(cookie);
    return {
        'Authorization': 'Bearer $_bearerToken',
        'x-csrf-token': ct0,
        'Cookie': cookie,
        'Content-Type': form
            ? 'application/x-www-form-urlencoded'
            : 'application/json',
        'User-Agent': kUserAgent,
        'Origin': 'https://x.com',
        'Referer': 'https://x.com/',
        'x-twitter-active-user': 'yes',
        'x-twitter-auth-type': 'OAuth2Session',
        'x-twitter-client-language': 'ja',
        'x-client-transaction-id': _generateTransactionId(),
    };
  }

  /// HTTP通信をDebugLogServiceに記録
  void _logResponse(
    String label,
    String method,
    Uri uri,
    Map<String, String> headers,
    String? requestBody,
    http.Response response,
    Stopwatch sw,
  ) {
    // response.bodyの参照を保持しない（500KB+のGC遅延を防止）
    final bodySnippet = response.body.length > 2048
        ? '${response.body.substring(0, 2048)}... [${response.body.length} bytes]'
        : response.body;
    DebugLogService.instance.logHttp(
      tag: 'XApi',
      method: method,
      url: uri.toString(),
      requestHeaders: headers,
      requestBody: requestBody,
      statusCode: response.statusCode,
      responseHeaders: response.headers,
      responseBody: bodySnippet,
      duration: sw.elapsed,
      extra: {'label': label},
    );
  }

  /// ミューテーション前にGETで最新 Cookie を取得しマージする
  /// ブラウザが自動で行う Cookie 更新を再現する
  Future<String> _warmCookies(XCredentials creds) async {
    try {
      // account/settings.json は404を返すため、通知件数API（軽量GET）で代替
      final uri = Uri.parse(
          XEndpoints.badgeCount);
      final response = await _client.get(uri, headers: _buildHeaders(creds));

      debugPrint('[XApi] warmCookies: status=${response.statusCode}');

      final setCookie = response.headers['set-cookie'];
      if (setCookie == null || setCookie.isEmpty) {
        debugPrint('[XApi] warmCookies: no set-cookie header');
        return creds.cookieHeader;
      }

      // 既存 Cookie をパース
      final merged = <String, String>{};
      for (final pair in creds.cookieHeader.split('; ')) {
        final eq = pair.indexOf('=');
        if (eq > 0) {
          merged[pair.substring(0, eq).trim()] = pair.substring(eq + 1);
        }
      }

      // Set-Cookie を個別の cookie ごとに分割してパース
      // Set-Cookie ヘッダーは "name=value; path=/; ..., name2=value2; ..." 形式
      final setCookieParts = setCookie.split(RegExp(r',\s*(?=[A-Za-z_]+=)'));
      final updated = <String>[];
      for (final part in setCookieParts) {
        final m = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)=([^;]*)').firstMatch(part.trim());
        if (m != null) {
          final name = m.group(1)!;
          final value = m.group(2)!;
          if (merged.containsKey(name) && merged[name] != value) {
            updated.add(name);
          }
          merged[name] = value; // 既存にないCookieも追加
        }
      }

      debugPrint('[XApi] warmCookies: updated=[${updated.join(",")}] total=${merged.length}');

      // ct0 が更新された場合は内部トラッカーも更新
      final ct0Val = merged['ct0'];
      if (ct0Val != null) _latestCt0[creds.authToken] = ct0Val;

      return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
    } catch (e) {
      debugPrint('[XApi] warmCookies error: $e');
      return creds.cookieHeader;
    }
  }

  // ===== queryId 404 リトライラッパー =====

  /// GET 系 API の 404 リトライ (対象 operation の queryId のみ更新)
  Future<T> _withTargetedQueryIdRetry<T>(
    XCredentials creds,
    String operationName,
    Future<T> Function(String queryId) action,
  ) async {
    var queryId = XQueryIdService.instance.getQueryId(operationName, creds: creds);
    // queryId が空なら先にリフレッシュ
    if (queryId.isEmpty) {
      await XQueryIdService.instance.forceRefresh(creds, onlyUpdate: {operationName});
      queryId = XQueryIdService.instance.getQueryId(operationName, creds: creds);
      if (queryId.isEmpty) return await action(queryId); // 空のまま進めてエラーにする
    }
    try {
      return await action(queryId);
    } on XApiException catch (e) {
      if (e.statusCode == 404) {
        final count = await XQueryIdService.instance
            .forceRefresh(creds, onlyUpdate: {operationName});
        debugPrint('[XApi] 404→targeted refresh ($count ids) for $operationName');
        final newQueryId = XQueryIdService.instance.getQueryId(operationName, creds: creds);
        if (newQueryId != queryId) return await action(newQueryId);
      }
      rethrow;
    }
  }

  /// Mutation 系は queryId を動的に取得するだけ (404 リトライしない)
  /// mutation の 404 はアカウント制限や削除済みツイート等が多いため
  String _getMutationQueryId(String operationName, XCredentials creds) =>
      XQueryIdService.instance.getQueryId(operationName, creds: creds);

  /// タイムラインを取得
  Future<({List<Post> posts, String? cursor})> getTimeline(
    XCredentials creds, {
    String? accountId,
    int count = 20,
    String? cursor,
  }) async {
    await _ensureBearerToken(creds);
    return _withTargetedQueryIdRetry(creds, 'HomeLatestTimeline', (queryId) async {
      final variables = json.encode({
        'count': count,
        'includePromotedContent': false,
        'latestControlAvailable': true,
        if (cursor != null) 'cursor': cursor,
      });

      final features = json.encode(XFeatures.forOperation('HomeLatestTimeline'));

      final uri = Uri.parse(
        '${XEndpoints.graphqlBase}/$queryId/HomeLatestTimeline'
        '?variables=${Uri.encodeComponent(variables)}'
        '&features=${Uri.encodeComponent(features)}',
      );

      final hdrs = _buildHeaders(creds);
      final sw = Stopwatch()..start();
      final response = await _withRateLimitRetry(
        () => _client.get(uri, headers: hdrs),
      );
      sw.stop();
      _updateCt0FromResponse(creds, response);
      _logResponse('HomeLatestTimeline', 'GET', uri, hdrs, null, response, sw);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw XAuthException('Authentication failed: ${response.statusCode}');
      }

      if (response.statusCode != 200) {
        throw XApiException(
          'Failed to fetch timeline: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final result = await compute(_parseXTimelineInIsolate, (response.body, accountId));

      // queryId品質チェック: ユーザー情報が大量に欠けていたらデフォルトに戻す
      if (result.posts.length >= 3) {
        final missingCount = result.posts.where((p) =>
            p.username.isEmpty || p.handle == '@').length;
        final missingRatio = missingCount / result.posts.length;
        if (missingRatio > 0.5) {
          debugPrint('[XApi] WARNING: ${(missingRatio * 100).toInt()}% of posts missing user info '
              '(queryId=$queryId). Reverting HomeLatestTimeline to default.');
          await XQueryIdService.instance.revertToDefault(creds, 'HomeLatestTimeline');
        }
      }

      return result;
    });
  }

  /// ツイート詳細 (リプライ含む) を取得
  Future<List<Post>> getTweetDetail(
    XCredentials creds,
    String tweetId, {
    String? accountId,
  }) async {
    await _ensureBearerToken(creds);
    return _withTargetedQueryIdRetry(creds, 'TweetDetail', (queryId) async {
      final variables = json.encode({
        'focalTweetId': tweetId,
        'with_rux_injections': false,
        'includePromotedContent': false,
        'withCommunity': true,
        'withQuickPromoteEligibilityTweetFields': true,
        'withBirdwatchNotes': true,
        'withVoice': true,
        'withV2Timeline': true,
      });

      final features = json.encode(XFeatures.forOperation('TweetDetail'));

      final uri = Uri.parse(
        '${XEndpoints.graphqlBase}/$queryId/TweetDetail'
        '?variables=${Uri.encodeComponent(variables)}'
        '&features=${Uri.encodeComponent(features)}',
      );

      final hdrs = _buildHeaders(creds);
      final sw = Stopwatch()..start();
      final response = await _withRateLimitRetry(
        () => _client.get(uri, headers: hdrs),
      );
      sw.stop();
      _updateCt0FromResponse(creds, response);
      _logResponse('TweetDetail', 'GET', uri, hdrs, null, response, sw);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw XAuthException('Authentication failed: ${response.statusCode}');
      }

      if (response.statusCode != 200) {
        throw XApiException(
          'Failed to fetch tweet detail: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      return parseTweetDetailResponse(body, accountId);
    });
  }

  // ===== エンゲージメント API (GraphQL) =====

  static String _snippet(String body) =>
      body.length > 200 ? body.substring(0, 200) : body;

  /// GraphQL mutation のレスポンスを解析して XApiResult を生成
  /// ステータス200でもボディに errors が含まれていれば失敗扱いにする
  XApiResult _parseMutationResult(http.Response response) {
    var success = response.statusCode == 200;
    int statusCode = response.statusCode;

    if (success) {
      try {
        final body = json.decode(response.body);
        if (body is Map<String, dynamic>) {
          final errors = body['errors'] as List<dynamic>?;
          if (errors != null && errors.isNotEmpty) {
            success = false;
            // エラーコードを抽出（X GraphQL の errors[0].code）
            final firstError = errors[0] as Map<String, dynamic>?;
            final code = firstError?['code'] as int?;
            if (code != null) statusCode = code;
          }
        }
      } catch (_) {}
    }

    return XApiResult(
      success: success,
      statusCode: statusCode,
      bodySnippet: _snippet(response.body),
    );
  }

  /// いいね
  Future<bool> likeTweet(XCredentials creds, String tweetId) async =>
      (await likeTweetWithDetail(creds, tweetId)).success;

  Future<XApiResult> likeTweetWithDetail(
      XCredentials creds, String tweetId) async {
    final queryId = _getMutationQueryId('FavoriteTweet', creds);
    final warmedCookies = await _warmCookies(creds);
    final uri =
        Uri.parse('${XEndpoints.graphqlBase}/$queryId/FavoriteTweet');
    final hdrs = _buildHeaders(creds, cookieOverride: warmedCookies);
    final reqBody = json.encode({
      'variables': {'tweet_id': tweetId},
      'queryId': queryId,
    });
    final sw = Stopwatch()..start();
    final response = await _withRateLimitRetry(
      () => _client.post(uri, headers: hdrs, body: reqBody),
      maxRetries: 1,
    );
    sw.stop();
    _logResponse('FavoriteTweet', 'POST', uri, hdrs, reqBody, response, sw);
    return _parseMutationResult(response);
  }

  /// いいね解除
  Future<bool> unlikeTweet(XCredentials creds, String tweetId) async =>
      (await unlikeTweetWithDetail(creds, tweetId)).success;

  Future<XApiResult> unlikeTweetWithDetail(
      XCredentials creds, String tweetId) async {
    final queryId = _getMutationQueryId('UnfavoriteTweet', creds);
    final warmedCookies = await _warmCookies(creds);
    final uri =
        Uri.parse('${XEndpoints.graphqlBase}/$queryId/UnfavoriteTweet');
    final hdrs = _buildHeaders(creds, cookieOverride: warmedCookies);
    final reqBody = json.encode({
      'variables': {'tweet_id': tweetId},
      'queryId': queryId,
    });
    final sw = Stopwatch()..start();
    final response = await _withRateLimitRetry(
      () => _client.post(uri, headers: hdrs, body: reqBody),
      maxRetries: 1,
    );
    sw.stop();
    _logResponse('UnfavoriteTweet', 'POST', uri, hdrs, reqBody, response, sw);
    return _parseMutationResult(response);
  }

  Future<XApiResult> retweetWithDetail(
      XCredentials creds, String tweetId) async {
    final queryId = _getMutationQueryId('CreateRetweet', creds);
    final warmedCookies = await _warmCookies(creds);
    final uri =
        Uri.parse('${XEndpoints.graphqlBase}/$queryId/CreateRetweet');
    final hdrs = _buildHeaders(creds, cookieOverride: warmedCookies);
    final reqBody = json.encode({
      'variables': {'tweet_id': tweetId},
      'queryId': queryId,
    });
    final sw = Stopwatch()..start();
    final response = await _withRateLimitRetry(
      () => _client.post(uri, headers: hdrs, body: reqBody),
      maxRetries: 1,
    );
    sw.stop();
    _logResponse('CreateRetweet', 'POST', uri, hdrs, reqBody, response, sw);
    return _parseMutationResult(response);
  }

  Future<XApiResult> unretweetWithDetail(
      XCredentials creds, String tweetId) async {
    final queryId = _getMutationQueryId('DeleteRetweet', creds);
    final warmedCookies = await _warmCookies(creds);
    final uri =
        Uri.parse('${XEndpoints.graphqlBase}/$queryId/DeleteRetweet');
    final hdrs = _buildHeaders(creds, cookieOverride: warmedCookies);
    final reqBody = json.encode({
      'variables': {'source_tweet_id': tweetId},
      'queryId': queryId,
    });
    final sw = Stopwatch()..start();
    final response = await _withRateLimitRetry(
      () => _client.post(uri, headers: hdrs, body: reqBody),
      maxRetries: 1,
    );
    sw.stop();
    _logResponse('DeleteRetweet', 'POST', uri, hdrs, reqBody, response, sw);
    return _parseMutationResult(response);
  }

  /// ユーザープロフィール取得 (UserByScreenName)
  /// 404 時は UserByScreenName の queryId のみ更新してリトライ
  Future<Map<String, dynamic>?> getUserProfile(
    XCredentials creds,
    String screenName,
  ) async {
    await _ensureBearerToken(creds);
    return _withTargetedQueryIdRetry(creds, 'UserByScreenName', (queryId) async {
      final variables = json.encode({
        'screen_name': screenName,
        'withSafetyModeUserFields': true,
      });

      final features = json.encode(XFeatures.forOperation('UserByScreenName'));

      final uri = Uri.parse(
        '${XEndpoints.graphqlBase}/$queryId/UserByScreenName'
        '?variables=${Uri.encodeComponent(variables)}'
        '&features=${Uri.encodeComponent(features)}',
      );

      final hdrs = _buildHeaders(creds);
      final sw = Stopwatch()..start();
      final response = await _withRateLimitRetry(
        () => _client.get(uri, headers: hdrs),
      );
      sw.stop();
      _updateCt0FromResponse(creds, response);
      _logResponse('UserByScreenName', 'GET', uri, hdrs, null, response, sw);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw XAuthException('Authentication failed: ${response.statusCode}');
      }
      if (response.statusCode != 200) {
        throw XApiException(
          'Failed to fetch user profile: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final body = json.decode(response.body) as Map<String, dynamic>;

      // 複数のレスポンスパスを試行
      var userResult = dig(body, ['data', 'user', 'result']) as Map<String, dynamic>?;
      userResult ??= dig(body, ['data', 'user_result', 'result']) as Map<String, dynamic>?;

      if (userResult == null) return null;

      // ユーザー結果がラッパー型の場合
      final userTypeName = userResult['__typename'] as String?;
      if (userTypeName != null && userTypeName != 'User' && userResult['user'] != null) {
        userResult = userResult['user'] as Map<String, dynamic>?;
        if (userResult == null) return null;
      }

      final restId = userResult['rest_id'] as String?;
      final legacy = userResult['legacy'] as Map<String, dynamic>?;

      if (legacy == null) {
        return {
          'rest_id': restId,
          'protected': (userResult['privacy'] as Map<String, dynamic>?)?['protected'] as bool? ?? false,
        };
      }

      final isFollowing = legacy['following'] as bool? ?? false;

      return {
        'rest_id': restId,
        'name': legacy['name'] as String?,
        'screen_name': legacy['screen_name'] as String?,
        'description': legacy['description'] as String?,
        'followers_count': legacy['followers_count'] as int? ?? 0,
        'friends_count': legacy['friends_count'] as int? ?? 0,
        'statuses_count': legacy['statuses_count'] as int? ?? 0,
        'profile_image_url_https': (legacy['profile_image_url_https'] as String?)
            ?.replaceFirst('_normal', '_400x400'),
        'profile_banner_url': legacy['profile_banner_url'] as String?,
        'is_following': isFollowing,
        'protected': legacy['protected'] as bool?
            ?? (userResult['privacy'] as Map<String, dynamic>?)?['protected'] as bool?
            ?? false,
      };
    });
  }

  /// ユーザーの投稿一覧取得 (UserTweets)
  /// 404 時は UserTweets の queryId のみ更新してリトライ
  /// Returns: ({posts, cursor}) — cursor は次ページ取得用
  Future<({List<Post> posts, String? cursor})> getUserTimeline(
    XCredentials creds,
    String userId, {
    String? accountId,
    int count = 20,
    String? cursor,
  }) async {
    await _ensureBearerToken(creds);
    return _withTargetedQueryIdRetry(creds, 'UserTweets', (queryId) async {
      final variables = json.encode({
        'userId': userId,
        'count': count,
        'includePromotedContent': false,
        'withQuickPromoteEligibilityTweetFields': true,
        'withVoice': true,
        'withV2Timeline': true,
        if (cursor != null) 'cursor': cursor,
      });

      final features = json.encode(XFeatures.forOperation('UserTweets'));

      final uri = Uri.parse(
        '${XEndpoints.graphqlBase}/$queryId/UserTweets'
        '?variables=${Uri.encodeComponent(variables)}'
        '&features=${Uri.encodeComponent(features)}',
      );

      final hdrs = _buildHeaders(creds);
      final sw = Stopwatch()..start();
      final response = await _withRateLimitRetry(
        () => _client.get(uri, headers: hdrs),
      );
      sw.stop();
      _updateCt0FromResponse(creds, response);
      _logResponse('UserTweets', 'GET', uri, hdrs, null, response, sw);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw XAuthException('Authentication failed: ${response.statusCode}');
      }
      if (response.statusCode != 200) {
        throw XApiException(
          'Failed to fetch user timeline: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      return _parseUserTimeline(body, accountId);
    });
  }

  /// 指定ユーザー(自分)のいいね一覧を取得 (Likes operation)
  /// [userId] は対象ユーザーの rest_id。
  /// 404 時は Likes の queryId のみ更新してリトライ。
  /// Returns: ({posts, cursor}) — cursor は次ページ取得用
  Future<({List<Post> posts, String? cursor})> getLikes(
    XCredentials creds,
    String userId, {
    String? accountId,
    int count = 20,
    String? cursor,
  }) async {
    await _ensureBearerToken(creds);
    return _withTargetedQueryIdRetry(creds, 'Likes', (queryId) async {
      final variables = json.encode({
        'userId': userId,
        'count': count,
        'includePromotedContent': false,
        'withClientEventToken': false,
        'withBirdwatchNotes': false,
        'withVoice': true,
        'withV2Timeline': true,
        if (cursor != null) 'cursor': cursor,
      });

      final features = json.encode(XFeatures.forOperation('Likes'));

      final uri = Uri.parse(
        '${XEndpoints.graphqlBase}/$queryId/Likes'
        '?variables=${Uri.encodeComponent(variables)}'
        '&features=${Uri.encodeComponent(features)}',
      );

      final hdrs = _buildHeaders(creds);
      final sw = Stopwatch()..start();
      final response = await _withRateLimitRetry(
        () => _client.get(uri, headers: hdrs),
      );
      sw.stop();
      _updateCt0FromResponse(creds, response);
      _logResponse('Likes', 'GET', uri, hdrs, null, response, sw);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw XAuthException('Authentication failed: ${response.statusCode}');
      }
      if (response.statusCode != 200) {
        throw XApiException(
          'Failed to fetch likes: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      return _parseUserTimeline(body, accountId);
    });
  }

  /// 自分のブックマーク一覧を取得 (Bookmarks operation, userId 不要)
  /// 404 時は Bookmarks の queryId のみ更新してリトライ。
  /// Returns: ({posts, cursor}) — cursor は次ページ取得用
  Future<({List<Post> posts, String? cursor})> getBookmarks(
    XCredentials creds, {
    String? accountId,
    int count = 20,
    String? cursor,
  }) async {
    await _ensureBearerToken(creds);
    return _withTargetedQueryIdRetry(creds, 'Bookmarks', (queryId) async {
      final variables = json.encode({
        'count': count,
        'includePromotedContent': true,
        if (cursor != null) 'cursor': cursor,
      });

      final features = json.encode(XFeatures.forOperation('Bookmarks'));

      final uri = Uri.parse(
        '${XEndpoints.graphqlBase}/$queryId/Bookmarks'
        '?variables=${Uri.encodeComponent(variables)}'
        '&features=${Uri.encodeComponent(features)}',
      );

      final hdrs = _buildHeaders(creds);
      final sw = Stopwatch()..start();
      final response = await _withRateLimitRetry(
        () => _client.get(uri, headers: hdrs),
      );
      sw.stop();
      _updateCt0FromResponse(creds, response);
      _logResponse('Bookmarks', 'GET', uri, hdrs, null, response, sw);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw XAuthException('Authentication failed: ${response.statusCode}');
      }
      if (response.statusCode != 200) {
        throw XApiException(
          'Failed to fetch bookmarks: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      return _parseUserTimeline(body, accountId);
    });
  }

  /// screenName から rest_id を解決 (自分のいいね一覧取得で userId が必要なため)
  Future<String?> getRestId(XCredentials creds, String screenName) async {
    final profile =
        await getUserProfile(creds, screenName.replaceFirst('@', ''));
    return profile?['rest_id'] as String?;
  }

  /// UserTweets レスポンスをパース (カーソル付き)
  ({List<Post> posts, String? cursor}) _parseUserTimeline(
      Map<String, dynamic> body, String? accountId) {
    final posts = <Post>[];
    String? nextCursor;
    try {
      // 複数のレスポンスパスを試行
      var instructions = dig(body, [
            'data',
            'user',
            'result',
            'timeline_v2',
            'timeline',
            'instructions',
          ]) as List<dynamic>?;
      instructions ??= dig(body, [
            'data',
            'user_result',
            'result',
            'timeline_v2',
            'timeline',
            'instructions',
          ]) as List<dynamic>?;
      instructions ??= dig(body, [
            'data',
            'user',
            'result',
            'timeline',
            'timeline',
            'instructions',
          ]) as List<dynamic>?;
      // ブックマーク (Bookmarks operation) のパス
      instructions ??= dig(body, [
            'data',
            'bookmark_timeline_v2',
            'timeline',
            'instructions',
          ]) as List<dynamic>?;

      if (instructions == null || instructions.isEmpty) {
        return (posts: posts, cursor: null);
      }

      for (final instruction in instructions) {
        final map = instruction as Map<String, dynamic>;
        if (map['type'] != 'TimelineAddEntries') continue;

        final entries = map['entries'] as List<dynamic>? ?? [];
        for (final entry in entries) {
          final entryMap = entry as Map<String, dynamic>;

          final entryId = entryMap['entryId'] as String? ?? '';
          if (entryId.startsWith('promoted-') ||
              entryId.startsWith('promotedTweet-')) {
            continue;
          }

          // カーソルエントリからページネーション情報を抽出
          if (entryId.startsWith('cursor-bottom-')) {
            final content = entryMap['content'] as Map<String, dynamic>?;
            final value = content?['value'] as String?;
            if (value != null) nextCursor = value;
            continue;
          }

          final content = entryMap['content'] as Map<String, dynamic>?;
          if (content == null) continue;

          final entryType = content['entryType'] as String?;
          if (entryType == 'TimelineTimelineCursor') {
            // 別形式のカーソル
            final cursorType = content['cursorType'] as String?;
            if (cursorType == 'Bottom') {
              nextCursor = content['value'] as String?;
            }
            continue;
          }
          if (entryType != 'TimelineTimelineItem') continue;

          final itemContent =
              content['itemContent'] as Map<String, dynamic>?;
          if (itemContent == null) continue;
          if (itemContent.containsKey('promotedMetadata')) continue;

          final tweetResults =
              itemContent['tweet_results'] as Map<String, dynamic>?;
          if (tweetResults == null) continue;

          final result = tweetResults['result'] as Map<String, dynamic>?;
          if (result == null) continue;

          final post = parseTweet(result, accountId);
          if (post != null) posts.add(post);
        }
      }
    } catch (e) {
      debugPrint('[XApi] Error parsing user timeline: $e');
    }
    return (posts: posts, cursor: nextCursor);
  }

  /// フォロー (REST API)
  Future<bool> followUser(XCredentials creds, String userId) async {
    final warmedCookies = await _warmCookies(creds);
    final uri = Uri.parse('https://x.com/i/api/1.1/friendships/create.json');
    final hdrs = _buildHeaders(creds, form: true, cookieOverride: warmedCookies);
    const reqBody = 'user_id=';
    final sw = Stopwatch()..start();
    final response = await _withRateLimitRetry(
      () => _client.post(uri, headers: hdrs, body: 'user_id=$userId'),
      maxRetries: 1,
    );
    sw.stop();
    _logResponse('followUser', 'POST', uri, hdrs, '$reqBody$userId', response, sw);
    return response.statusCode == 200;
  }

  /// フォロー解除 (REST API)
  Future<bool> unfollowUser(XCredentials creds, String userId) async {
    final warmedCookies = await _warmCookies(creds);
    final uri = Uri.parse('https://x.com/i/api/1.1/friendships/destroy.json');
    final hdrs = _buildHeaders(creds, form: true, cookieOverride: warmedCookies);
    final sw = Stopwatch()..start();
    final response = await _withRateLimitRetry(
      () => _client.post(uri, headers: hdrs, body: 'user_id=$userId'),
      maxRetries: 1,
    );
    sw.stop();
    _logResponse('unfollowUser', 'POST', uri, hdrs, 'user_id=$userId', response, sw);
    return response.statusCode == 200;
  }

  /// メンション（リプライ）通知を取得 (REST v2 API)
  Future<List<NotificationItem>> getMentionNotifications(
    XCredentials creds, {
    int count = 20,
  }) async {
    final params = {
      'include_profile_interstitial_type': '1',
      'include_blocking': '1',
      'include_blocked_by': '1',
      'include_followed_by': '1',
      'include_want_retweets': '1',
      'include_mute_edge': '1',
      'include_can_dm': '1',
      'include_can_media_tag': '1',
      'include_ext_is_blue_verified': '1',
      'include_ext_verified_type': '1',
      'include_ext_profile_image_shape': '1',
      'skip_status': '1',
      'cards_platform': 'Web-12',
      'include_cards': '1',
      'include_ext_alt_text': 'true',
      'include_ext_limited_action_results': 'true',
      'include_quote_count': 'true',
      'include_reply_count': '1',
      'tweet_mode': 'extended',
      'include_ext_views': 'true',
      'count': '$count',
      'ext': 'mediaStats,highlightedLabel,parodyCommentaryFanLabel,hasNftAvatar,voiceInfo,birdwatchPivot,superFollowMetadata,unmentionInfo,editControl',
    };

    final uri = Uri.https('x.com', '/i/api/2/notifications/mentions.json', params);
    final hdrs = _buildHeaders(creds);
    final sw = Stopwatch()..start();
    final response = await _withRateLimitRetry(
      () => _client.get(uri, headers: hdrs),
    );
    sw.stop();
    _updateCt0FromResponse(creds, response);
    _logResponse('Mentions', 'GET', uri, hdrs, null, response, sw);

    if (response.statusCode != 200) return [];

    try {
      final body = await compute(_jsonDecodeInIsolate, response.body);
      return _parseMentionNotifications(body);
    } catch (e) {
      debugPrint('[XApi] Error parsing mentions: $e');
      return [];
    }
  }

  List<NotificationItem> _parseMentionNotifications(Map<String, dynamic> body) {
    final notifications = <NotificationItem>[];
    try {
      final globalObjects = body['globalObjects'] as Map<String, dynamic>?;
      final tweets = globalObjects?['tweets'] as Map<String, dynamic>? ?? {};
      final users = globalObjects?['users'] as Map<String, dynamic>? ?? {};

      final timeline = body['timeline'] as Map<String, dynamic>?;
      final instructions = timeline?['instructions'] as List<dynamic>? ?? [];

      for (final instruction in instructions) {
        final map = instruction as Map<String, dynamic>;
        List<dynamic> entries = [];
        if (map.containsKey('addEntries')) {
          entries = (map['addEntries'] as Map<String, dynamic>)['entries'] as List<dynamic>? ?? [];
        }
        for (final entry in entries) {
          final entryMap = entry as Map<String, dynamic>;
          final entryId = entryMap['entryId'] as String? ?? '';
          if (entryId.startsWith('cursor-')) continue;

          // メンションエントリからツイートIDを取得（複数パスを試行）
          final content = entryMap['content'] as Map<String, dynamic>?;
          final item = content?['item'] as Map<String, dynamic>?;
          final itemContent = item?['content'] as Map<String, dynamic>?;
          String? tweetId = (itemContent?['tweet'] as Map<String, dynamic>?)?['id'] as String?;
          // フォールバック: notification形式
          tweetId ??= (itemContent?['notification'] as Map<String, dynamic>?)?['id'] as String?;
          // フォールバック: entryIdからtweet-XXXを抽出
          if (tweetId == null && entryId.startsWith('tweet-')) {
            tweetId = entryId.replaceFirst('tweet-', '');
          }
          if (tweetId == null) {
            debugPrint('[XApi] Mentions: skipped entry $entryId (no tweetId found)');
            continue;
          }

          final tweet = tweets[tweetId] as Map<String, dynamic>?;
          if (tweet == null) continue;

          final userId = tweet['user_id_str'] as String?;
          final user = userId != null ? users[userId] as Map<String, dynamic>? : null;
          final actorName = user?['name'] as String? ?? '';
          final actorHandle = '@${user?['screen_name'] as String? ?? ''}';
          final actorAvatarUrl = (user?['profile_image_url_https'] as String?)
              ?.replaceFirst('_normal', '_400x400');

          final fullText = _decodeHtmlEntities(tweet['full_text'] as String? ?? '');
          final createdAt = tweet['created_at'] as String?;
          final ts = createdAt != null ? parseTwitterDate(createdAt) : DateTime.now();

          // リプライかメンションかを判定
          final inReplyTo = tweet['in_reply_to_status_id_str'] as String?;
          final type = inReplyTo != null ? NotificationType.reply : NotificationType.mention;

          notifications.add(NotificationItem(
            id: 'x_mention_$tweetId',
            type: type,
            source: SnsService.x,
            actorName: actorName,
            actorHandle: actorHandle,
            actorAvatarUrl: actorAvatarUrl,
            targetPostBody: fullText,
            targetPostId: tweetId,
            timestamp: ts,
          ));
        }
      }
    } catch (e) {
      debugPrint('[XApi] Error in _parseMentionNotifications: $e');
    }
    debugPrint('[XApi] Mentions parsed: ${notifications.length} '
        '(replies: ${notifications.where((n) => n.type == NotificationType.reply).length}, '
        'mentions: ${notifications.where((n) => n.type == NotificationType.mention).length})');
    return notifications;
  }

  /// 通知を GraphQL API (GenericTimelineById) で取得
  /// 他のqueryIdに影響しないよう、リトライ機構を使わない
  Future<({List<NotificationItem> notifications, bool ok})> getNotificationsGraphQL(
    XCredentials creds, {
    String? accountId,
  }) async {
    await _ensureBearerToken(creds);
    const opName = 'NotificationsTimeline';

    Future<List<NotificationItem>> attempt(String queryId, String opName) async {
      final variables = json.encode({
        'count': 40,
        'includePromotedContent': false,
        'timeline_type': 'All',
      });
      final features = json.encode(XFeatures.forOperation('NotificationsTimeline'));

      final uri = Uri.parse(
        '${XEndpoints.graphqlBase}/$queryId/$opName'
        '?variables=${Uri.encodeComponent(variables)}'
        '&features=${Uri.encodeComponent(features)}',
      );

      final hdrs = _buildHeaders(creds);
      final sw = Stopwatch()..start();
      final response = await _client.get(uri, headers: hdrs);
      sw.stop();
      _updateCt0FromResponse(creds, response);
      _logResponse('NotificationsGQL', 'GET', uri, hdrs, null, response, sw);

      if (response.statusCode != 200) {
        return <NotificationItem>[];
      }

      final body = json.decode(response.body) as Map<String, dynamic>;

      // エラーレスポンスの検出（200 + errors）
      final errors = body['errors'] as List<dynamic>?;
      if (errors != null && errors.isNotEmpty) {
        throw XApiException(
          'NotificationsGQL errors: ${errors.first}',
          statusCode: 500,
        );
      }

      return _parseGraphQLNotifications(body, accountId);
    }

    final queryId = XQueryIdService.instance.getQueryId(opName, creds: creds);
    if (queryId.isEmpty) {
      return (notifications: <NotificationItem>[], ok: false);
    }

    try {
      final list = await attempt(queryId, opName);
      return (notifications: list, ok: true);
    } on XApiException {
      debugPrint('[XApi] $opName failed');
    } catch (e) {
      debugPrint('[XApi] $opName error: $e');
    }

    return (notifications: <NotificationItem>[], ok: false);
  }

  List<NotificationItem> _parseGraphQLNotifications(
      Map<String, dynamic> body, String? accountId) {
    final notifications = <NotificationItem>[];
    try {
      // レスポンスパス: data.viewer.timeline.timeline.instructions
      final instructions = dig(body, [
            'data', 'viewer', 'timeline', 'timeline', 'instructions',
          ]) as List<dynamic>? ??
          // フォールバック: 別パス
          dig(body, ['data', 'viewer_v2', 'user_results', 'result',
            'notification_timeline', 'timeline', 'instructions'])
              as List<dynamic>? ??
          [];

      for (final instruction in instructions) {
        final map = instruction as Map<String, dynamic>;
        if (map['type'] != 'TimelineAddEntries') continue;

        final entries = map['entries'] as List<dynamic>? ?? [];
        for (final entry in entries) {
          final entryMap = entry as Map<String, dynamic>;
          final entryId = entryMap['entryId'] as String? ?? '';
          if (entryId.startsWith('cursor-')) continue;
          if (!entryId.startsWith('notification-')) continue;

          final content = entryMap['content'] as Map<String, dynamic>?;
          if (content == null) continue;

          final entryType = content['entryType'] as String?;
          if (entryType == 'TimelineTimelineItem') {
            _parseGQLNotificationItem(content, entryId, accountId, notifications);
          } else if (entryType == 'TimelineTimelineModule') {
            // グループ化された通知（会話スレッド等）
            final items = content['items'] as List<dynamic>? ?? [];
            for (final item in items) {
              final itemMap = item as Map<String, dynamic>;
              final itemContent = itemMap['item'] as Map<String, dynamic>?;
              if (itemContent == null) continue;
              _parseGQLNotificationItem(itemContent, entryId, accountId, notifications);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[XApi] Error in _parseGraphQLNotifications: $e');
    }
    debugPrint('[XApi] GraphQL notifications parsed: ${notifications.length}');
    return notifications;
  }

  void _parseGQLNotificationItem(
    Map<String, dynamic> content,
    String entryId,
    String? accountId,
    List<NotificationItem> notifications,
  ) {
    final itemContent = content['itemContent'] as Map<String, dynamic>?;
    if (itemContent == null) return;
    final itemType = itemContent['itemType'] as String? ?? '';

    if (itemType == 'TimelineNotification') {
      // 通知メタ情報（いいね、RT、フォロー等）
      // この中にはツイートデータが直接含まれない場合がある
      // REST APIのall.jsonで取得済みなのでスキップ
      return;
    }

    // TimelineTweet: リプライ/メンション/引用等のツイートベース通知
    if (itemType != 'TimelineTweet') return;

    final tweetResults = itemContent['tweet_results'] as Map<String, dynamic>?;
    final result = tweetResults?['result'] as Map<String, dynamic>?;
    if (result == null) return;

    final post = parseTweet(result, accountId);
    if (post == null) return;

    // in_reply_to があればリプライ、なければメンション
    final legacy = (result['legacy'] ?? result['tweet']?['legacy']) as Map<String, dynamic>?;
    final inReplyTo = legacy?['in_reply_to_status_id_str'] as String?;
    final type = inReplyTo != null ? NotificationType.reply : NotificationType.mention;

    notifications.add(NotificationItem(
      id: 'x_gql_${post.id}',
      type: type,
      source: SnsService.x,
      actorName: post.username,
      actorHandle: '@${post.handle}',
      actorAvatarUrl: post.avatarUrl,
      targetPostBody: post.body,
      targetPostId: post.id.replaceFirst('x_', ''),
      timestamp: post.timestamp,
    ));
  }

  /// 通知一覧を取得 (REST v2 API)
  Future<({List<NotificationItem> notifications, String? cursor, String? responseSnippet})>
      getNotifications(
    XCredentials creds, {
    int count = 40,
    String? cursor,
  }) async {
    await _ensureBearerToken(creds);
    final params = {
      'include_profile_interstitial_type': '1',
      'include_blocking': '1',
      'include_blocked_by': '1',
      'include_followed_by': '1',
      'include_want_retweets': '1',
      'include_mute_edge': '1',
      'include_can_dm': '1',
      'include_can_media_tag': '1',
      'include_ext_is_blue_verified': '1',
      'include_ext_verified_type': '1',
      'include_ext_profile_image_shape': '1',
      'skip_status': '1',
      'cards_platform': 'Web-12',
      'include_cards': '1',
      'include_ext_alt_text': 'true',
      'include_ext_limited_action_results': 'true',
      'include_quote_count': 'true',
      'include_reply_count': '1',
      'tweet_mode': 'extended',
      'include_ext_views': 'true',
      'count': '$count',
      if (cursor != null) 'cursor': cursor,
      'ext': 'mediaStats,highlightedLabel,parodyCommentaryFanLabel,hasNftAvatar,voiceInfo,birdwatchPivot,superFollowMetadata,unmentionInfo,editControl',
    };

    final uri = Uri.https('x.com', XEndpoints.notificationsAll, params);

    final hdrs = _buildHeaders(creds);
    final sw = Stopwatch()..start();
    final response = await _withRateLimitRetry(
      () => _client.get(uri, headers: hdrs),
    );
    sw.stop();
    _updateCt0FromResponse(creds, response);
    _logResponse('Notifications', 'GET', uri, hdrs, null, response, sw);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw XAuthException('Authentication failed: ${response.statusCode}');
    }
    if (response.statusCode != 200) {
      throw XApiException(
        'Failed to fetch notifications: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final body = await compute(_jsonDecodeInIsolate, response.body);
    final result = _parseNotifications(body);
    return (
      notifications: result.notifications,
      cursor: result.cursor,
      responseSnippet: '${result.debugInfo}',
    );
  }

  ({List<NotificationItem> notifications, String? cursor, String debugInfo}) _parseNotifications(
      Map<String, dynamic> body) {
    final notifications = <NotificationItem>[];
    String? nextCursor;

    try {
      final globalObjects = body['globalObjects'] as Map<String, dynamic>?;
      final tweets =
          globalObjects?['tweets'] as Map<String, dynamic>? ?? {};
      final users =
          globalObjects?['users'] as Map<String, dynamic>? ?? {};

      final notifMap =
          globalObjects?['notifications'] as Map<String, dynamic>? ?? {};

      final timeline = body['timeline'] as Map<String, dynamic>?;
      final instructions = timeline?['instructions'] as List<dynamic>? ?? [];

      final orderedIds = <String>[];
      for (final instruction in instructions) {
        final map = instruction as Map<String, dynamic>;

        List<dynamic> entries = [];
        if (map.containsKey('addEntries')) {
          final addEntries = map['addEntries'] as Map<String, dynamic>;
          entries = addEntries['entries'] as List<dynamic>? ?? [];
        }

        if (entries.isEmpty) continue;

        for (final entry in entries) {
          final entryMap = entry as Map<String, dynamic>;
          final entryId = entryMap['entryId'] as String? ?? '';

          if (entryId.startsWith('cursor-bottom-')) {
            final content = entryMap['content'] as Map<String, dynamic>?;
            final op = content?['operation'] as Map<String, dynamic>?;
            final cursor = op?['cursor'] as Map<String, dynamic>?;
            nextCursor = cursor?['value'] as String?;
            continue;
          }
          if (entryId.startsWith('cursor-')) continue;

          final content = entryMap['content'] as Map<String, dynamic>?;
          if (content == null) continue;

          String? id = (content['notification'] as Map<String, dynamic>?)?['id'] as String?;
          if (id == null) {
            final item = content['item'] as Map<String, dynamic>?;
            final itemContent = item?['content'] as Map<String, dynamic>?;
            id = (itemContent?['notification'] as Map<String, dynamic>?)?['id'] as String?;
          }
          if (id == null && entryId.startsWith('notification-')) {
            id = entryId.replaceFirst('notification-', '');
          }

          if (id != null) orderedIds.add(id);
        }
      }

      for (final notifId in orderedIds) {
        final notif = notifMap[notifId] as Map<String, dynamic>?;
        if (notif == null) continue;

        final icon = notif['icon'] as Map<String, dynamic>?;
        final iconId = icon?['id'] as String? ?? '';
        final message = notif['message'] as Map<String, dynamic>?;
        final messageText = message?['text'] as String? ?? '';

        final type = switch (iconId) {
          'heart_icon' => NotificationType.like,
          'retweet_icon' => NotificationType.repost,
          'person_icon' => NotificationType.follow,
          'reply_icon' => NotificationType.reply,
          'at_icon' || 'mention_icon' => NotificationType.mention,
          'quote_icon' || 'retweet_with_comment_icon' => NotificationType.quote,
          _ => NotificationType.unknown,
        };
        if (type == NotificationType.unknown && iconId.isNotEmpty) {
          debugPrint('[XApi] Unknown notification icon: $iconId (message: $messageText)');
        }
        final timestampMs = notif['timestampMs'] as String? ?? '0';
        final ts = DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(timestampMs) ?? 0);

        // ユーザー情報
        final userActions =
            notif['template']?['aggregateUserActionsV1'] as Map<String, dynamic>?;
        final targetObjects =
            userActions?['targetObjects'] as List<dynamic>? ?? [];
        final fromUserIds =
            userActions?['fromUsers'] as List<dynamic>? ?? [];

        String actorName = '';
        String actorHandle = '';
        String? actorAvatarUrl;
        final additionalActors = <NotificationActor>[];

        if (fromUserIds.isNotEmpty) {
          for (var i = 0; i < fromUserIds.length; i++) {
            final userId = fromUserIds[i]?['user']?['id'] as String?;
            if (userId == null) continue;
            final user = users[userId] as Map<String, dynamic>?;
            if (user == null) continue;

            final name = user['name'] as String? ?? '';
            final handle = '@${user['screen_name'] as String? ?? ''}';
            final avatar = (user['profile_image_url_https'] as String?)
                ?.replaceFirst('_normal', '_400x400');

            if (i == 0) {
              actorName = name;
              actorHandle = handle;
              actorAvatarUrl = avatar;
            } else {
              additionalActors.add(NotificationActor(
                name: name,
                handle: handle,
                avatarUrl: avatar,
              ));
            }
          }
        }

        // メッセージからアクター名を抽出 (fromUsers が空の場合)
        if (actorName.isEmpty && messageText.isNotEmpty) {
          actorName = messageText.split('さんが').firstOrNull ??
              messageText.split(' liked').firstOrNull ??
              messageText;
        }

        // 対象ツイートのテキスト
        String? targetPostBody;
        String? targetPostId;
        if (targetObjects.isNotEmpty) {
          final tweetId = targetObjects.first?['tweet']?['id'] as String?;
          if (tweetId != null) {
            final tweet = tweets[tweetId] as Map<String, dynamic>?;
            final rawBody = tweet?['full_text'] as String?;
            targetPostBody = rawBody != null ? _decodeHtmlEntities(rawBody) : null;
            targetPostId = tweetId;
          }
        }

        notifications.add(NotificationItem(
          id: 'x_notif_$notifId',
          type: type,
          source: SnsService.x,
          actorName: actorName,
          actorHandle: actorHandle,
          actorAvatarUrl: actorAvatarUrl,
          additionalActors: additionalActors,
          targetPostBody: targetPostBody,
          targetPostId: targetPostId,
          timestamp: ts,
        ));
      }
    } catch (e) {
      debugPrint('[XApi] Error parsing notifications: $e');
    }
    return (
      notifications: notifications,
      cursor: nextCursor,
      debugInfo: 'notif=${notifications.length}',
    );
  }

  @visibleForTesting
  List<Post> parseTimeline(Map<String, dynamic> body, String? accountId) {
    return parseTimelineWithCursor(body, accountId).posts;
  }

  ({List<Post> posts, String? cursor}) parseTimelineWithCursor(
      Map<String, dynamic> body, String? accountId) {
    final posts = <Post>[];
    String? nextCursor;

    try {
      // HomeTimeline / HomeLatestTimeline 両方のパスを試す
      var instructions = dig(body, [
            'data',
            'home',
            'home_timeline_urt',
            'instructions',
          ]) as List<dynamic>?;

      // HomeLatestTimeline の別パス候補
      instructions ??= dig(body, [
            'data',
            'home_latest',
            'home_latest_timeline_urt',
            'instructions',
          ]) as List<dynamic>?;

      // さらに別パス (latest_timeline)
      instructions ??= dig(body, [
            'data',
            'home',
            'latest_timeline',
            'instructions',
          ]) as List<dynamic>?;

      if (instructions == null || instructions.isEmpty) {
        instructions = [];
      }

      for (final instruction in instructions) {
        final map = instruction as Map<String, dynamic>;
        if (map['type'] != 'TimelineAddEntries') continue;

        final entries = map['entries'] as List<dynamic>? ?? [];
        for (final entry in entries) {
          final entryMap = entry as Map<String, dynamic>;

          // 広告・プロモーションを除外
          final entryId = entryMap['entryId'] as String? ?? '';
          if (entryId.startsWith('promoted-') ||
              entryId.startsWith('promotedTweet-')) {
            continue;
          }

          // カーソルエントリからページネーション情報を抽出
          if (entryId.startsWith('cursor-bottom-')) {
            final content = entryMap['content'] as Map<String, dynamic>?;
            final value = content?['value'] as String?;
            if (value != null) nextCursor = value;
            continue;
          }

          final content = entryMap['content'] as Map<String, dynamic>?;
          if (content == null) continue;

          final entryType = content['entryType'] as String?;
          if (entryType == 'TimelineTimelineCursor') {
            final cursorType = content['cursorType'] as String?;
            if (cursorType == 'Bottom') {
              nextCursor = content['value'] as String?;
            }
            continue;
          }
          if (entryType != 'TimelineTimelineItem') continue;

          final itemContent = content['itemContent'] as Map<String, dynamic>?;
          if (itemContent == null) continue;

          // promotedMetadata があれば広告なのでスキップ
          if (itemContent.containsKey('promotedMetadata')) continue;

          final tweetResults =
              itemContent['tweet_results'] as Map<String, dynamic>?;
          if (tweetResults == null) continue;

          final result = tweetResults['result'] as Map<String, dynamic>?;
          if (result == null) continue;

          final post = parseTweet(result, accountId);
          if (post != null) posts.add(post);
        }
      }
    } catch (e) {
      debugPrint('[XApi] Error parsing timeline: $e');
    }

    return (posts: posts, cursor: nextCursor);
  }

  @visibleForTesting
  List<Post> parseTweetDetailResponse(
      Map<String, dynamic> body, String? accountId) {
    final posts = <Post>[];
    try {
      final instructions = dig(body, [
            'data',
            'threaded_conversation_with_injections_v2',
            'instructions',
          ]) as List<dynamic>? ??
          [];

      for (final instruction in instructions) {
        final map = instruction as Map<String, dynamic>;
        if (map['type'] != 'TimelineAddEntries') continue;

        final entries = map['entries'] as List<dynamic>? ?? [];
        for (final entry in entries) {
          final entryMap = entry as Map<String, dynamic>;
          final entryId = entryMap['entryId'] as String? ?? '';

          // リプライと元ツイートのみ。関連ツイート・おすすめ等を除外
          if (!entryId.startsWith('tweet-') &&
              !entryId.startsWith('conversationthread-')) {
            continue;
          }

          final content = entryMap['content'] as Map<String, dynamic>?;
          if (content == null) continue;

          final entryType = content['entryType'] as String?;
          if (entryType == 'TimelineTimelineItem') {
            final itemContent =
                content['itemContent'] as Map<String, dynamic>?;
            if (itemContent == null) continue;
            final tweetResults =
                itemContent['tweet_results'] as Map<String, dynamic>?;
            if (tweetResults == null) continue;
            final result = tweetResults['result'] as Map<String, dynamic>?;
            if (result == null) continue;
            final post = parseTweet(result, accountId);
            if (post != null) posts.add(post);
          } else if (entryType == 'TimelineTimelineModule') {
            // Conversation module (replies)
            final items = content['items'] as List<dynamic>? ?? [];
            for (final item in items) {
              final itemMap = item as Map<String, dynamic>;
              final itemContent =
                  itemMap['item']?['itemContent'] as Map<String, dynamic>?;
              if (itemContent == null) continue;
              final tweetResults =
                  itemContent['tweet_results'] as Map<String, dynamic>?;
              if (tweetResults == null) continue;
              final result = tweetResults['result'] as Map<String, dynamic>?;
              if (result == null) continue;
              final post = parseTweet(result, accountId);
              if (post != null) posts.add(post);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[XApi] Error parsing tweet detail: $e');
    }
    return posts;
  }

  @visibleForTesting
  Post? parseTweet(Map<String, dynamic> result, String? accountId) {
    try {
      // __typename が TweetWithVisibilityResults の場合
      final typeName = result['__typename'] as String?;
      final tweetData = typeName == 'TweetWithVisibilityResults'
          ? result['tweet'] as Map<String, dynamic>?
          : result;
      if (tweetData == null) return null;

      final legacy = tweetData['legacy'] as Map<String, dynamic>?;
      if (legacy == null) return null;

      final core = tweetData['core'] as Map<String, dynamic>?;
      final userResults =
          core?['user_results'] as Map<String, dynamic>?;
      var userResult = userResults?['result'] as Map<String, dynamic>?;

      // ユーザー結果がラッパー型の場合 (User 以外の __typename)
      final userTypeName = userResult?['__typename'] as String?;
      if (userTypeName != null && userTypeName != 'User' && userResult?['user'] != null) {
        userResult = userResult!['user'] as Map<String, dynamic>?;
      }

      final userLegacy = userResult?['legacy'] as Map<String, dynamic>?;

      // ユーザー名: legacy → core → userResult直下 の順にフォールバック
      var username = userLegacy?['name'] as String? ?? '';
      var screenName = userLegacy?['screen_name'] as String? ?? '';
      if (username.isEmpty) {
        username = core?['name'] as String?
            ?? userResult?['core']?['name'] as String?
            ?? '';
      }
      if (screenName.isEmpty) {
        screenName = core?['screen_name'] as String?
            ?? userResult?['core']?['screen_name'] as String?
            ?? '';
      }

      // --- 通常RT検出: legacy.retweeted_status_result ---
      final retweetedStatusResult =
          legacy['retweeted_status_result'] as Map<String, dynamic>?;
      if (retweetedStatusResult != null) {
        final innerResult =
            retweetedStatusResult['result'] as Map<String, dynamic>?;
        if (innerResult != null) {
          final originalPost = parseTweet(innerResult, accountId);
          if (originalPost != null) {
            // RT時刻を使用（元ツイートの時刻だとソート時に古い位置に移動してしまう）
            final rtCreatedAt = legacy['created_at'] as String? ?? '';
            return originalPost.copyWith(
              isRetweet: true,
              retweetedByUsername: username,
              retweetedByHandle: '@$screenName',
              isSensitive: originalPost.isSensitive,
              timestamp: rtCreatedAt.isNotEmpty
                  ? parseTwitterDate(rtCreatedAt)
                  : null,
            );
          }
        }
      }

      final tweetId = legacy['id_str'] as String? ?? '${result.hashCode}';
      var fullText = _decodeHtmlEntities(legacy['full_text'] as String? ?? '');
      final createdAt = legacy['created_at'] as String? ?? '';

      // アバター: legacy → userResult.avatar → core の順にフォールバック
      var avatarUrlRaw =
          userLegacy?['profile_image_url_https'] as String?;
      avatarUrlRaw ??= (userResult?['avatar'] as Map<String, dynamic>?)?['image_url'] as String?;
      // _normal (48x48) → _400x400 に置換して高解像度版を取得
      final avatarUrl = avatarUrlRaw?.replaceFirst('_normal', '_400x400');

      // Sensitive content flag
      final isSensitive = legacy['possibly_sensitive'] as bool? ?? false;

      // Protected account flag: legacy → userResult.privacy.protected の順にフォールバック
      final isProtected = userLegacy?['protected'] as bool?
          ?? (userResult?['privacy'] as Map<String, dynamic>?)?['protected'] as bool?
          ?? false;

      // Engagement counts
      final likeCount = legacy['favorite_count'] as int? ?? 0;
      final repostCount = legacy['retweet_count'] as int? ?? 0;
      final replyCount = legacy['reply_count'] as int? ?? 0;
      final isFavorited = legacy['favorited'] as bool? ?? false;
      final isRetweeted = legacy['retweeted'] as bool? ?? false;

      // Reply info
      final inReplyToId = legacy['in_reply_to_status_id_str'] as String?;

      // Media extraction
      final imageUrls = <String>[];
      String? videoUrl;
      String? videoThumbnailUrl;

      final extendedEntities =
          legacy['extended_entities'] as Map<String, dynamic>?;
      final mediaList =
          extendedEntities?['media'] as List<dynamic>? ?? [];

      for (final media in mediaList) {
        final m = media as Map<String, dynamic>;
        final type = m['type'] as String?;
        if (type == 'photo') {
          final url = m['media_url_https'] as String?;
          if (url != null) imageUrls.add(url);
        } else if (type == 'video' || type == 'animated_gif') {
          videoThumbnailUrl = m['media_url_https'] as String?;
          // Get highest bitrate video variant
          final videoInfo = m['video_info'] as Map<String, dynamic>?;
          final variants = videoInfo?['variants'] as List<dynamic>? ?? [];
          int maxBitrate = -1;
          for (final v in variants) {
            final vm = v as Map<String, dynamic>;
            final contentType = vm['content_type'] as String?;
            if (contentType != 'video/mp4') continue;
            final bitrate = vm['bitrate'] as int? ?? 0;
            if (bitrate > maxBitrate) {
              maxBitrate = bitrate;
              videoUrl = vm['url'] as String?;
            }
          }
        }
      }

      // t.co URL expansion
      final entities = legacy['entities'] as Map<String, dynamic>?;
      final urls = entities?['urls'] as List<dynamic>? ?? [];
      for (final urlObj in urls) {
        final u = urlObj as Map<String, dynamic>;
        final shortUrl = u['url'] as String?;
        final expandedUrl = u['expanded_url'] as String?;
        if (shortUrl != null && expandedUrl != null) {
          fullText = fullText.replaceAll(shortUrl, expandedUrl);
        }
      }

      // Remove trailing media URLs from text (t.co links for images/videos)
      for (final media in mediaList) {
        final m = media as Map<String, dynamic>;
        final mediaUrl = m['url'] as String?;
        if (mediaUrl != null) {
          fullText = fullText.replaceAll(mediaUrl, '').trimRight();
        }
      }

      // --- 引用RT検出: quoted_status_result ---
      Post? quotedPost;
      final quotedStatusResult =
          tweetData['quoted_status_result'] as Map<String, dynamic>?;
      if (quotedStatusResult != null) {
        final quotedResult =
            quotedStatusResult['result'] as Map<String, dynamic>?;
        if (quotedResult != null) {
          quotedPost = parseTweet(quotedResult, accountId);
        }
      }

      // Remove quote tweet URL from text (trailing https://x.com/.../status/...)
      if (quotedPost != null) {
        fullText = fullText
            .replaceAll(RegExp(r'https?://(?:x|twitter)\.com/\S+/status/\S+$'), '')
            .trimRight();
      }

      // Permalink
      final permalink = screenName.isNotEmpty
          ? 'https://x.com/$screenName/status/$tweetId'
          : null;

      return Post(
        id: 'x_$tweetId',
        source: SnsService.x,
        username: username,
        handle: '@$screenName',
        body: fullText,
        timestamp: parseTwitterDate(createdAt),
        avatarUrl: avatarUrl,
        accountId: accountId,
        likeCount: likeCount,
        repostCount: repostCount,
        replyCount: replyCount,
        likedByAccountIds: isFavorited && accountId != null ? {accountId} : null,
        repostedByAccountIds: isRetweeted && accountId != null ? {accountId} : null,
        imageUrls: imageUrls,
        videoUrl: videoUrl,
        videoThumbnailUrl: videoThumbnailUrl,
        permalink: permalink,
        inReplyToId: inReplyToId,
        quotedPost: quotedPost,
        isSensitive: isSensitive,
        isProtected: isProtected,
      );
    } catch (e) {
      debugPrint('[XApi] Error parsing tweet: $e');
      return null;
    }
  }

  /// Twitter の日付フォーマット "Wed Oct 10 20:19:24 +0000 2018" をパース
  @visibleForTesting
  DateTime parseTwitterDate(String dateStr) {
    try {
      // "Wed Oct 10 20:19:24 +0000 2018"
      final parts = dateStr.split(' ');
      if (parts.length < 6) return DateTime.now();

      const months = {
        'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04',
        'May': '05', 'Jun': '06', 'Jul': '07', 'Aug': '08',
        'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12',
      };

      final month = months[parts[1]] ?? '01';
      final day = parts[2].padLeft(2, '0');
      final time = parts[3];
      final year = parts[5];

      return DateTime.parse('$year-$month-${day}T${time}Z');
    } catch (_) {
      return DateTime.now();
    }
  }

  @visibleForTesting
  dynamic dig(Map<String, dynamic> map, List<String> keys) {
    dynamic current = map;
    for (final key in keys) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }
}

class XApiResult {
  const XApiResult({
    required this.success,
    required this.statusCode,
    this.bodySnippet,
    this.apiRoute,
    this.requestInfo,
  });

  final bool success;
  final int statusCode;
  final String? bodySnippet;

  /// 使用した API 経路 ('GraphQL' | 'REST v1.1')
  final String? apiRoute;

  /// リクエストの詳細（デバッグ用）
  final String? requestInfo;
}

class XApiException implements Exception {
  XApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'XApiException: $message';
}

class XAuthException implements Exception {
  XAuthException(this.message);
  final String message;
  @override
  String toString() => 'XAuthException: $message';
}

/// compute() 用: json.decode + タイムラインパースを別Isolateで実行
({List<Post> posts, String? cursor}) _parseXTimelineInIsolate(
    (String responseBody, String? accountId) args) {
  final body = json.decode(args.$1) as Map<String, dynamic>;
  // parseTweet等は純粋関数（インスタンス状態を使わない）ので安全
  return XApiService.instance.parseTimelineWithCursor(body, args.$2);
}

/// compute() 用: json.decodeだけを別Isolateで実行
Map<String, dynamic> _jsonDecodeInIsolate(String responseBody) {
  return json.decode(responseBody) as Map<String, dynamic>;
}
