import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import 'x_query_id_service.dart';

class XApiService {
  XApiService._();
  static final instance = XApiService._();

  // X の公開 Bearer Token (Web クライアント用)
  static const _bearerToken =
      'AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs'
      '%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA';

  Map<String, String> _buildHeaders(XCredentials creds, {bool form = false}) => {
        'Authorization': 'Bearer $_bearerToken',
        'x-csrf-token': creds.ct0,
        'Cookie': creds.cookieHeader,
        'Content-Type': form
            ? 'application/x-www-form-urlencoded'
            : 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'x-twitter-active-user': 'yes',
        'x-twitter-auth-type': 'OAuth2Session',
        'x-twitter-client-language': 'ja',
      };

  // ===== queryId 404 リトライラッパー =====

  /// GET 系 API (throw するもの) の 404 リトライラッパー
  Future<T> _withQueryIdRetry<T>(
    XCredentials creds,
    String operationName,
    Future<T> Function(String queryId) action,
  ) async {
    final queryId = XQueryIdService.instance.getQueryId(operationName);
    try {
      return await action(queryId);
    } on XApiException catch (e) {
      if (e.statusCode == 404) {
        debugPrint('[XApi] 404 detected for $operationName, refreshing queryIds...');
        final count = await XQueryIdService.instance.forceRefresh(creds);
        debugPrint('[XApi] Refreshed $count queryIds');
        final newQueryId = XQueryIdService.instance.getQueryId(operationName);
        if (newQueryId != queryId) {
          debugPrint('[XApi] Retrying $operationName with new queryId: $newQueryId');
          return await action(newQueryId);
        }
      }
      rethrow;
    }
  }

  /// Mutation 系は queryId を動的に取得するだけ (404 リトライしない)
  /// mutation の 404 はアカウント制限や削除済みツイート等が多いため
  String _getMutationQueryId(String operationName) =>
      XQueryIdService.instance.getQueryId(operationName);

  /// タイムラインを取得
  Future<List<Post>> getTimeline(
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

      final features = json.encode({
        'rweb_tipjar_consumption_enabled': true,
        'responsive_web_graphql_exclude_directive_enabled': true,
        'verified_phone_label_enabled': false,
        'creator_subscriptions_tweet_preview_api_enabled': true,
        'responsive_web_graphql_timeline_navigation_enabled': true,
        'responsive_web_graphql_skip_user_profile_image_extensions_enabled':
            false,
        'communities_web_enable_tweet_community_results_fetch': true,
        'c9s_tweet_anatomy_moderator_badge_enabled': true,
        'articles_preview_enabled': true,
        'responsive_web_edit_tweet_api_enabled': true,
        'graphql_is_translatable_rweb_tweet_is_translatable_enabled': true,
        'view_counts_everywhere_api_enabled': true,
        'longform_notetweets_consumption_enabled': true,
        'responsive_web_twitter_article_tweet_consumption_enabled': true,
        'tweet_awards_web_tipping_enabled': false,
        'creator_subscriptions_quote_tweet_preview_enabled': false,
        'freedom_of_speech_not_reach_fetch_enabled': true,
        'standardized_nudges_misinfo': true,
        'tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled':
            true,
        'rweb_video_timestamps_enabled': true,
        'longform_notetweets_rich_text_read_enabled': true,
        'longform_notetweets_inline_media_enabled': true,
        'responsive_web_enhance_cards_enabled': false,
      });

      final uri = Uri.parse(
        'https://x.com/i/api/graphql/$queryId/HomeLatestTimeline'
        '?variables=${Uri.encodeComponent(variables)}'
        '&features=${Uri.encodeComponent(features)}',
      );

      final response = await http.get(uri, headers: _buildHeaders(creds));

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
      debugPrint('[XApi] Response top keys: ${body.keys.toList()}');
      return _parseTimeline(body, accountId);
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

      final features = json.encode({
        'rweb_tipjar_consumption_enabled': true,
        'responsive_web_graphql_exclude_directive_enabled': true,
        'verified_phone_label_enabled': false,
        'creator_subscriptions_tweet_preview_api_enabled': true,
        'responsive_web_graphql_timeline_navigation_enabled': true,
        'responsive_web_graphql_skip_user_profile_image_extensions_enabled':
            false,
        'communities_web_enable_tweet_community_results_fetch': true,
        'c9s_tweet_anatomy_moderator_badge_enabled': true,
        'articles_preview_enabled': true,
        'responsive_web_edit_tweet_api_enabled': true,
        'graphql_is_translatable_rweb_tweet_is_translatable_enabled': true,
        'view_counts_everywhere_api_enabled': true,
        'longform_notetweets_consumption_enabled': true,
        'responsive_web_twitter_article_tweet_consumption_enabled': true,
        'tweet_awards_web_tipping_enabled': false,
        'creator_subscriptions_quote_tweet_preview_enabled': false,
        'freedom_of_speech_not_reach_fetch_enabled': true,
        'standardized_nudges_misinfo': true,
        'tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled':
            true,
        'rweb_video_timestamps_enabled': true,
        'longform_notetweets_rich_text_read_enabled': true,
        'longform_notetweets_inline_media_enabled': true,
        'responsive_web_enhance_cards_enabled': false,
      });

      final uri = Uri.parse(
        'https://x.com/i/api/graphql/$queryId/TweetDetail'
        '?variables=${Uri.encodeComponent(variables)}'
        '&features=${Uri.encodeComponent(features)}',
      );

      final response = await http.get(uri, headers: _buildHeaders(creds));

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
      return _parseTweetDetailResponse(body, accountId);
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
    final queryId = _getMutationQueryId('FavoriteTweet');
    final uri =
        Uri.parse('https://x.com/i/api/graphql/$queryId/FavoriteTweet');
    final response = await http.post(
      uri,
      headers: _buildHeaders(creds),
      body: json.encode({
        'variables': {'tweet_id': tweetId},
        'queryId': queryId,
      }),
    );
    debugPrint('[XApi] likeTweet $tweetId: ${response.statusCode}');
    debugPrint('[XApi] likeTweet body: ${_snippet(response.body)}');
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
    final queryId = _getMutationQueryId('UnfavoriteTweet');
    final uri =
        Uri.parse('https://x.com/i/api/graphql/$queryId/UnfavoriteTweet');
    final response = await http.post(
      uri,
      headers: _buildHeaders(creds),
      body: json.encode({
        'variables': {'tweet_id': tweetId},
        'queryId': queryId,
      }),
    );
    debugPrint('[XApi] unlikeTweet $tweetId: ${response.statusCode}');
    debugPrint('[XApi] unlikeTweet body: ${_snippet(response.body)}');
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
    final queryId = _getMutationQueryId('CreateRetweet');
    final uri =
        Uri.parse('https://x.com/i/api/graphql/$queryId/CreateRetweet');
    final response = await http.post(
      uri,
      headers: _buildHeaders(creds),
      body: json.encode({
        'variables': {'tweet_id': tweetId, 'dark_request': false},
        'queryId': queryId,
      }),
    );
    debugPrint('[XApi] retweet $tweetId: ${response.statusCode}');
    debugPrint('[XApi] retweet body: ${_snippet(response.body)}');
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
    final queryId = _getMutationQueryId('DeleteRetweet');
    final uri =
        Uri.parse('https://x.com/i/api/graphql/$queryId/DeleteRetweet');
    final response = await http.post(
      uri,
      headers: _buildHeaders(creds),
      body: json.encode({
        'variables': {'source_tweet_id': tweetId, 'dark_request': false},
        'queryId': queryId,
      }),
    );
    debugPrint('[XApi] unretweet $tweetId: ${response.statusCode}');
    debugPrint('[XApi] unretweet body: ${_snippet(response.body)}');
    return XApiResult(
      success: response.statusCode == 200,
      statusCode: response.statusCode,
      bodySnippet: _snippet(response.body),
    );
  }

  List<Post> _parseTimeline(Map<String, dynamic> body, String? accountId) {
    final posts = <Post>[];

    try {
      // HomeTimeline / HomeLatestTimeline 両方のパスを試す
      var instructions = _dig(body, [
            'data',
            'home',
            'home_timeline_urt',
            'instructions',
          ]) as List<dynamic>?;

      // HomeLatestTimeline の別パス候補
      instructions ??= _dig(body, [
            'data',
            'home_latest',
            'home_latest_timeline_urt',
            'instructions',
          ]) as List<dynamic>?;

      // さらに別パス (latest_timeline)
      instructions ??= _dig(body, [
            'data',
            'home',
            'latest_timeline',
            'instructions',
          ]) as List<dynamic>?;

      if (instructions == null || instructions.isEmpty) {
        // デバッグ: data 直下のキーを出力
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null) {
          debugPrint('[XApi] data keys: ${data.keys.toList()}');
          for (final key in data.keys) {
            final v = data[key];
            if (v is Map<String, dynamic>) {
              debugPrint('[XApi] data.$key keys: ${v.keys.toList()}');
            }
          }
        }
        instructions = [];
      }

      for (final instruction in instructions) {
        final map = instruction as Map<String, dynamic>;
        if (map['type'] != 'TimelineAddEntries') continue;

        final entries = map['entries'] as List<dynamic>? ?? [];
        for (final entry in entries) {
          final entryMap = entry as Map<String, dynamic>;
          final content = entryMap['content'] as Map<String, dynamic>?;
          if (content == null) continue;

          final entryType = content['entryType'] as String?;
          if (entryType != 'TimelineTimelineItem') continue;

          final itemContent = content['itemContent'] as Map<String, dynamic>?;
          if (itemContent == null) continue;

          final tweetResults =
              itemContent['tweet_results'] as Map<String, dynamic>?;
          if (tweetResults == null) continue;

          final result = tweetResults['result'] as Map<String, dynamic>?;
          if (result == null) continue;

          final post = _parseTweet(result, accountId);
          if (post != null) posts.add(post);
        }
      }
    } catch (e) {
      debugPrint('[XApi] Error parsing timeline: $e');
    }

    return posts;
  }

  List<Post> _parseTweetDetailResponse(
      Map<String, dynamic> body, String? accountId) {
    final posts = <Post>[];
    try {
      final instructions = _dig(body, [
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
            final post = _parseTweet(result, accountId);
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
              final post = _parseTweet(result, accountId);
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

  Post? _parseTweet(Map<String, dynamic> result, String? accountId) {
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
      final userResult = userResults?['result'] as Map<String, dynamic>?;
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
          final originalPost = _parseTweet(innerResult, accountId);
          if (originalPost != null) {
            return originalPost.copyWith(
              isRetweet: true,
              retweetedByUsername: username,
              retweetedByHandle: '@$screenName',
            );
          }
        }
      }

      final tweetId = legacy['id_str'] as String? ?? '${result.hashCode}';
      var fullText = legacy['full_text'] as String? ?? '';
      final createdAt = legacy['created_at'] as String? ?? '';

      final avatarUrl =
          userLegacy?['profile_image_url_https'] as String?;

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
          quotedPost = _parseTweet(quotedResult, accountId);
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
        timestamp: _parseTwitterDate(createdAt),
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
      );
    } catch (e) {
      debugPrint('[XApi] Error parsing tweet: $e');
      return null;
    }
  }

  /// Twitter の日付フォーマット "Wed Oct 10 20:19:24 +0000 2018" をパース
  DateTime _parseTwitterDate(String dateStr) {
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

  dynamic _dig(Map<String, dynamic> map, List<String> keys) {
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
  });

  final bool success;
  final int statusCode;
  final String? bodySnippet;
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
