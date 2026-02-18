import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/post.dart';
import '../models/sns_service.dart';

class XApiService {
  XApiService._();
  static final instance = XApiService._();

  // X の公開 Bearer Token (Web クライアント用)
  static const _bearerToken =
      'AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs'
      '%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA';

  // HomeLatestTimeline (Following) の GraphQL queryId
  // NOTE: この値は X のデプロイにより変更される場合がある
  static const _homeLatestTimelineQueryId = 'BKB7oi212Fi7kQtCBGE4zA';

  /// タイムラインを取得
  Future<List<Post>> getTimeline(
    XCredentials creds, {
    String? accountId,
    int count = 20,
  }) async {
    final variables = json.encode({
      'count': count,
      'includePromotedContent': false,
      'latestControlAvailable': true,
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
      'https://x.com/i/api/graphql/$_homeLatestTimelineQueryId/HomeLatestTimeline'
      '?variables=${Uri.encodeComponent(variables)}'
      '&features=${Uri.encodeComponent(features)}',
    );

    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $_bearerToken',
      'x-csrf-token': creds.ct0,
      'Cookie': 'auth_token=${creds.authToken}; ct0=${creds.ct0}',
      'Content-Type': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'x-twitter-active-user': 'yes',
      'x-twitter-client-language': 'ja',
    });

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw XAuthException('Authentication failed: ${response.statusCode}');
    }

    if (response.statusCode != 200) {
      throw XApiException(
        'Failed to fetch timeline: ${response.statusCode}',
      );
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    debugPrint('[XApi] Response top keys: ${body.keys.toList()}');
    return _parseTimeline(body, accountId);
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

      final tweetId = legacy['id_str'] as String? ?? '${result.hashCode}';
      final fullText = legacy['full_text'] as String? ?? '';
      final createdAt = legacy['created_at'] as String? ?? '';

      final username = userLegacy?['name'] as String? ?? '';
      final screenName = userLegacy?['screen_name'] as String? ?? '';
      final avatarUrl =
          userLegacy?['profile_image_url_https'] as String?;

      return Post(
        id: 'x_$tweetId',
        source: SnsService.x,
        username: username,
        handle: '@$screenName',
        body: fullText,
        timestamp: _parseTwitterDate(createdAt),
        avatarUrl: avatarUrl,
        accountId: accountId,
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

class XApiException implements Exception {
  XApiException(this.message);
  final String message;
  @override
  String toString() => 'XApiException: $message';
}

class XAuthException implements Exception {
  XAuthException(this.message);
  final String message;
  @override
  String toString() => 'XAuthException: $message';
}
