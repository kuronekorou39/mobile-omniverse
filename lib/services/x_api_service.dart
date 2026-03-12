import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;

import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/notification_item.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import 'debug_log_service.dart';
import 'x_bearer_token_service.dart';
import 'x_features.dart';
import 'x_query_id_service.dart';

class XApiService {
  XApiService._();
  static final instance = XApiService._();

  @visibleForTesting
  http.Client? httpClientOverride;

  String get _bearerToken => XBearerTokenService.instance.token;

  /// 最新の ct0 をアカウント別に追跡 (APIレスポンスの Set-Cookie で更新)
  final Map<String, String> _latestCt0 = {};

  /// authToken をキーにして最新 ct0 を取得
  String _getCt0(XCredentials creds) {
    return _latestCt0[creds.authToken] ?? creds.ct0;
  }

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

  http.Client get _client => httpClientOverride ?? http.Client();

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
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
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
    DebugLogService.instance.logHttp(
      tag: 'XApi',
      method: method,
      url: uri.toString(),
      requestHeaders: headers,
      requestBody: requestBody,
      statusCode: response.statusCode,
      responseHeaders: response.headers,
      responseBody: response.body,
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
          'https://x.com/i/api/2/badge_count/badge_count.json?supports_ntab_urt=1');
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

  /// GET 系 API (throw するもの) の 404 リトライラッパー
  /// queryId はアカウント別に管理 — 他アカウントに影響しない
  Future<T> _withQueryIdRetry<T>(
    XCredentials creds,
    String operationName,
    Future<T> Function(String queryId) action,
  ) async {
    final queryId = XQueryIdService.instance.getQueryId(operationName, creds: creds);
    try {
      return await action(queryId);
    } on XApiException catch (e) {
      if (e.statusCode == 404) {
        final count = await XQueryIdService.instance.forceRefresh(creds);
        debugPrint('[XApi] 404→queryId refresh ($count ids) for $operationName');
        final newQueryId = XQueryIdService.instance.getQueryId(operationName, creds: creds);
        if (newQueryId != queryId) return await action(newQueryId);
      }
      rethrow;
    }
  }

  /// GET 系 API の 404 リトライ (対象 operation の queryId のみ更新)
  Future<T> _withTargetedQueryIdRetry<T>(
    XCredentials creds,
    String operationName,
    Future<T> Function(String queryId) action,
  ) async {
    final queryId = XQueryIdService.instance.getQueryId(operationName, creds: creds);
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
    return _withQueryIdRetry(creds, 'HomeLatestTimeline', (queryId) async {
      final variables = json.encode({
        'count': count,
        'includePromotedContent': false,
        'latestControlAvailable': true,
        if (cursor != null) 'cursor': cursor,
      });

      final features = json.encode(XFeatures.timeline);

      final uri = Uri.parse(
        'https://x.com/i/api/graphql/$queryId/HomeLatestTimeline'
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

      final body = json.decode(response.body) as Map<String, dynamic>;
      return parseTimelineWithCursor(body, accountId);
    });
  }

  /// ツイート詳細 (リプライ含む) を取得
  Future<List<Post>> getTweetDetail(
    XCredentials creds,
    String tweetId, {
    String? accountId,
  }) async {
    return _withQueryIdRetry(creds, 'TweetDetail', (queryId) async {
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

      final features = json.encode(XFeatures.timeline);

      final uri = Uri.parse(
        'https://x.com/i/api/graphql/$queryId/TweetDetail'
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

  /// いいね
  Future<bool> likeTweet(XCredentials creds, String tweetId) async =>
      (await likeTweetWithDetail(creds, tweetId)).success;

  Future<XApiResult> likeTweetWithDetail(
      XCredentials creds, String tweetId) async {
    final queryId = _getMutationQueryId('FavoriteTweet', creds);
    final warmedCookies = await _warmCookies(creds);
    final uri =
        Uri.parse('https://x.com/i/api/graphql/$queryId/FavoriteTweet');
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
    return XApiResult(
      success: response.statusCode == 200,
      statusCode: response.statusCode,
      bodySnippet: _snippet(response.body),
    );
  }

  /// いいね解除
  Future<bool> unlikeTweet(XCredentials creds, String tweetId) async =>
      (await unlikeTweetWithDetail(creds, tweetId)).success;

  Future<XApiResult> unlikeTweetWithDetail(
      XCredentials creds, String tweetId) async {
    final queryId = _getMutationQueryId('UnfavoriteTweet', creds);
    final warmedCookies = await _warmCookies(creds);
    final uri =
        Uri.parse('https://x.com/i/api/graphql/$queryId/UnfavoriteTweet');
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
    return XApiResult(
      success: response.statusCode == 200,
      statusCode: response.statusCode,
      bodySnippet: _snippet(response.body),
    );
  }

  /// リツイート
  Future<bool> retweet(XCredentials creds, String tweetId) async =>
      (await retweetWithDetail(creds, tweetId)).success;

  Future<XApiResult> retweetWithDetail(
      XCredentials creds, String tweetId) async {
    final queryId = _getMutationQueryId('CreateRetweet', creds);
    final warmedCookies = await _warmCookies(creds);
    final uri =
        Uri.parse('https://x.com/i/api/graphql/$queryId/CreateRetweet');
    final hdrs = _buildHeaders(creds, cookieOverride: warmedCookies);
    final reqBody = json.encode({
      'variables': {'tweet_id': tweetId, 'dark_request': false},
      'queryId': queryId,
    });
    final sw = Stopwatch()..start();
    final response = await _withRateLimitRetry(
      () => _client.post(uri, headers: hdrs, body: reqBody),
      maxRetries: 1,
    );
    sw.stop();
    _logResponse('CreateRetweet', 'POST', uri, hdrs, reqBody, response, sw);
    return XApiResult(
      success: response.statusCode == 200,
      statusCode: response.statusCode,
      bodySnippet: _snippet(response.body),
    );
  }

  /// リツイート解除
  Future<bool> unretweet(XCredentials creds, String tweetId) async =>
      (await unretweetWithDetail(creds, tweetId)).success;

  Future<XApiResult> unretweetWithDetail(
      XCredentials creds, String tweetId) async {
    final queryId = _getMutationQueryId('DeleteRetweet', creds);
    final warmedCookies = await _warmCookies(creds);
    final uri =
        Uri.parse('https://x.com/i/api/graphql/$queryId/DeleteRetweet');
    final hdrs = _buildHeaders(creds, cookieOverride: warmedCookies);
    final reqBody = json.encode({
      'variables': {'source_tweet_id': tweetId, 'dark_request': false},
      'queryId': queryId,
    });
    final sw = Stopwatch()..start();
    final response = await _withRateLimitRetry(
      () => _client.post(uri, headers: hdrs, body: reqBody),
      maxRetries: 1,
    );
    sw.stop();
    _logResponse('DeleteRetweet', 'POST', uri, hdrs, reqBody, response, sw);
    return XApiResult(
      success: response.statusCode == 200,
      statusCode: response.statusCode,
      bodySnippet: _snippet(response.body),
    );
  }

  /// ユーザープロフィール取得 (UserByScreenName)
  /// 404 時は UserByScreenName の queryId のみ更新してリトライ
  Future<Map<String, dynamic>?> getUserProfile(
    XCredentials creds,
    String screenName,
  ) async {
    return _withTargetedQueryIdRetry(creds, 'UserByScreenName', (queryId) async {
      final variables = json.encode({
        'screen_name': screenName,
        'withSafetyModeUserFields': true,
      });

      final features = json.encode(XFeatures.userProfile);

      final uri = Uri.parse(
        'https://x.com/i/api/graphql/$queryId/UserByScreenName'
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

      if (legacy == null) return {'rest_id': restId};

      final isFollowing = legacy['following'] as bool? ?? false;

      return {
        'rest_id': restId,
        'name': legacy['name'] as String?,
        'screen_name': legacy['screen_name'] as String?,
        'description': legacy['description'] as String?,
        'followers_count': legacy['followers_count'] as int? ?? 0,
        'friends_count': legacy['friends_count'] as int? ?? 0,
        'statuses_count': legacy['statuses_count'] as int? ?? 0,
        'profile_image_url_https': legacy['profile_image_url_https'] as String?,
        'profile_banner_url': legacy['profile_banner_url'] as String?,
        'is_following': isFollowing,
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

      final features = json.encode(XFeatures.timeline);

      final uri = Uri.parse(
        'https://x.com/i/api/graphql/$queryId/UserTweets'
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

  /// ツイートを投稿 (GraphQL CreateTweet)
  /// 226 (bot detection) の場合はリトライせず即失敗を返す
  Future<XApiResult> createTweet(XCredentials creds, String text) async {
    // --- Cookie 詳細 (key=value の先頭16文字ずつ) ---
    final cookiePairs = <String>[];
    for (final pair in creds.cookieHeader.split('; ')) {
      final eq = pair.indexOf('=');
      if (eq > 0) {
        final name = pair.substring(0, eq);
        final val = pair.substring(eq + 1);
        final preview = val.length > 16 ? '${val.substring(0, 16)}…' : val;
        cookiePairs.add('$name=$preview');
      }
    }

    final warmedCookies = await _warmCookies(creds);

    // warmed で変化した Cookie を検出
    final warmedMap = <String, String>{};
    for (final pair in warmedCookies.split('; ')) {
      final eq = pair.indexOf('=');
      if (eq > 0) warmedMap[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    final origMap = <String, String>{};
    for (final pair in creds.cookieHeader.split('; ')) {
      final eq = pair.indexOf('=');
      if (eq > 0) origMap[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    final changedCookies = <String>[];
    for (final key in warmedMap.keys) {
      if (origMap[key] != warmedMap[key]) {
        changedCookies.add(key);
      }
    }

    // --- GraphQL CreateTweet ---
    final queryId = _getMutationQueryId('CreateTweet', creds);
    final gqlUri =
        Uri.parse('https://x.com/i/api/graphql/$queryId/CreateTweet');
    final headers = _buildHeaders(creds, cookieOverride: warmedCookies);

    // リクエスト詳細を構築（アクティビティログ用）
    final reqLines = StringBuffer();
    reqLines.writeln('=== Headers ===');
    for (final entry in headers.entries) {
      if (entry.key == 'Cookie') {
        reqLines.writeln('Cookie: (${entry.value.length} chars)');
      } else {
        reqLines.writeln('${entry.key}: ${entry.value}');
      }
    }
    reqLines.writeln('=== Cookies (orig) ===');
    for (final p in cookiePairs) {
      reqLines.writeln(p);
    }
    if (changedCookies.isNotEmpty) {
      reqLines.writeln('=== warmCookies changed ===');
      for (final key in changedCookies) {
        final oldVal = origMap[key] ?? '(none)';
        final newVal = warmedMap[key] ?? '(none)';
        reqLines.writeln('$key: ${oldVal.length > 16 ? "${oldVal.substring(0,16)}…" : oldVal} → ${newVal.length > 16 ? "${newVal.substring(0,16)}…" : newVal}');
      }
    } else {
      reqLines.writeln('=== warmCookies: no changes ===');
    }
    reqLines.writeln('=== Endpoint ===');
    reqLines.writeln('POST $gqlUri');
    reqLines.writeln('queryId=$queryId');
    final reqInfo = reqLines.toString();

    debugPrint('[XApi] createTweet POST:\n$reqInfo');
    final gqlBody = json.encode({
      'variables': {
        'tweet_text': text,
        'media': {'media_entities': [], 'possibly_sensitive': false},
        'semantic_annotation_ids': <dynamic>[],
        'disallowed_reply_options': null,
      },
      'features': XFeatures.createTweet,
      'queryId': queryId,
    });
    final sw = Stopwatch()..start();
    final gqlResponse = await _client.post(
      gqlUri,
      headers: headers,
      body: gqlBody,
    );
    sw.stop();
    _updateCt0FromResponse(creds, gqlResponse);
    _logResponse('CreateTweet', 'POST', gqlUri, headers, gqlBody, gqlResponse, sw);
    debugPrint('[XApi] createTweet(gql): ${gqlResponse.statusCode} body=${_snippet(gqlResponse.body)}');

    // GraphQL の成功判定
    bool gqlSuccess = gqlResponse.statusCode == 200;
    bool has226 = false;
    String? errorSummary;
    if (gqlSuccess) {
      try {
        final body = json.decode(gqlResponse.body);
        if (body is Map<String, dynamic> && body.containsKey('errors')) {
          final errors = body['errors'] as List<dynamic>?;
          if (errors != null && errors.isNotEmpty) {
            // エラー概要を生成（アクティビティログ用）
            final codes = errors
                .whereType<Map>()
                .map((e) => 'code=${e['code']} ${e['message'] ?? ''}')
                .join('; ');
            errorSummary = codes;
            has226 = errors.any((e) => e is Map && e['code'] == 226);
            gqlSuccess = false;
            if (!has226) {
              debugPrint('[XApi] createTweet(gql): errors: $codes');
            }
          }
        }
      } catch (_) {}
    } else {
      errorSummary = 'HTTP ${gqlResponse.statusCode}';
    }

    if (gqlSuccess) {
      return XApiResult(
        success: true,
        statusCode: gqlResponse.statusCode,
        bodySnippet: 'OK',
        apiRoute: 'GraphQL',
        requestInfo: reqInfo,
      );
    }

    if (has226) {
      debugPrint('[XApi] createTweet: GraphQL 226 (bot detection)');
    }

    return XApiResult(
      success: false,
      statusCode: has226 ? 226 : gqlResponse.statusCode,
      bodySnippet: errorSummary ?? _snippet(gqlResponse.body),
      apiRoute: 'GraphQL',
      requestInfo: reqInfo,
    );
  }

  /// 通知一覧を取得 (REST v2 API)
  Future<({List<NotificationItem> notifications, String? cursor, String? responseSnippet})>
      getNotifications(
    XCredentials creds, {
    int count = 40,
    String? cursor,
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
      if (cursor != null) 'cursor': cursor,
      'ext': 'mediaStats,highlightedLabel,parodyCommentaryFanLabel,hasNftAvatar,voiceInfo,birdwatchPivot,superFollowMetadata,unmentionInfo,editControl',
    };

    final uri = Uri.https('x.com', '/i/api/2/notifications/all.json', params);

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

    final body = json.decode(response.body) as Map<String, dynamic>;
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

        final type = switch (iconId) {
          'heart_icon' => NotificationType.like,
          'retweet_icon' => NotificationType.repost,
          'person_icon' => NotificationType.follow,
          'reply_icon' => NotificationType.reply,
          _ => NotificationType.unknown,
        };

        final message = notif['message'] as Map<String, dynamic>?;
        final messageText = message?['text'] as String? ?? '';
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

        if (fromUserIds.isNotEmpty) {
          final firstUserId = fromUserIds.first?['user']?['id'] as String?;
          if (firstUserId != null) {
            final user = users[firstUserId] as Map<String, dynamic>?;
            if (user != null) {
              actorName = user['name'] as String? ?? '';
              actorHandle = '@${user['screen_name'] as String? ?? ''}';
              actorAvatarUrl =
                  user['profile_image_url_https'] as String?;
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
            targetPostBody = tweet?['full_text'] as String?;
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

      final username = userLegacy?['name'] as String? ?? '';
      final screenName = userLegacy?['screen_name'] as String? ?? '';

      // --- 通常RT検出: legacy.retweeted_status_result ---
      final retweetedStatusResult =
          legacy['retweeted_status_result'] as Map<String, dynamic>?;
      if (retweetedStatusResult != null) {
        final innerResult =
            retweetedStatusResult['result'] as Map<String, dynamic>?;
        if (innerResult != null) {
          final originalPost = parseTweet(innerResult, accountId);
          if (originalPost != null) {
            return originalPost.copyWith(
              isRetweet: true,
              retweetedByUsername: username,
              retweetedByHandle: '@$screenName',
              isSensitive: originalPost.isSensitive,
            );
          }
        }
      }

      final tweetId = legacy['id_str'] as String? ?? '${result.hashCode}';
      var fullText = legacy['full_text'] as String? ?? '';
      final createdAt = legacy['created_at'] as String? ?? '';

      final avatarUrl =
          userLegacy?['profile_image_url_https'] as String?;

      // Sensitive content flag
      final isSensitive = legacy['possibly_sensitive'] as bool? ?? false;

      // Engagement counts
      final likeCount = legacy['favorite_count'] as int? ?? 0;
      final repostCount = legacy['retweet_count'] as int? ?? 0;
      final replyCount = legacy['reply_count'] as int? ?? 0;
      final isLiked = legacy['favorited'] as bool? ?? false;
      final isReposted = legacy['retweeted'] as bool? ?? false;

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
        isLiked: isLiked,
        isReposted: isReposted,
        imageUrls: imageUrls,
        videoUrl: videoUrl,
        videoThumbnailUrl: videoThumbnailUrl,
        permalink: permalink,
        inReplyToId: inReplyToId,
        quotedPost: quotedPost,
        isSensitive: isSensitive,
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
