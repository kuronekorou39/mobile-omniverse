import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/post.dart';
import '../models/sns_service.dart';

class BlueskyApiService {
  BlueskyApiService._();
  static final instance = BlueskyApiService._();

  /// タイムラインを取得
  Future<List<Post>> getTimeline(
    BlueskyCredentials creds, {
    String? accountId,
    int limit = 30,
  }) async {
    final uri = Uri.parse(
      '${creds.pdsUrl}/xrpc/app.bsky.feed.getTimeline?limit=$limit',
    );

    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer ${creds.accessJwt}',
      'Accept': 'application/json',
    });

    if (response.statusCode == 401) {
      throw BlueskyAuthException('Token expired');
    }

    if (response.statusCode != 200) {
      // AT Protocol は期限切れトークンで 400 を返すことがある
      if (response.statusCode == 400) {
        try {
          final errBody = json.decode(response.body) as Map<String, dynamic>;
          final errCode = errBody['error'] as String?;
          debugPrint('[BlueskyApi] 400 error code: $errCode');
          if (errCode == 'ExpiredToken' || errCode == 'InvalidToken') {
            throw BlueskyAuthException('Token expired (400: $errCode)');
          }
        } catch (e) {
          if (e is BlueskyAuthException) rethrow;
        }
      }
      throw BlueskyApiException(
        'Failed to fetch timeline: ${response.statusCode}',
      );
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    final feed = body['feed'] as List<dynamic>? ?? [];

    return feed.map((item) => _parsePost(item, accountId)).toList();
  }

  Post _parsePost(dynamic item, String? accountId) {
    final feedItem = item as Map<String, dynamic>;
    final post = feedItem['post'] as Map<String, dynamic>;
    final author = post['author'] as Map<String, dynamic>;
    final record = post['record'] as Map<String, dynamic>;

    final uri = post['uri'] as String? ?? '';
    // AT URI format: at://did/app.bsky.feed.post/rkey
    final postId = uri.isNotEmpty ? uri.split('/').last : '${post.hashCode}';

    final createdAt = record['createdAt'] as String? ?? '';

    return Post(
      id: 'bsky_$postId',
      source: SnsService.bluesky,
      username: author['displayName'] as String? ??
          author['handle'] as String? ??
          '',
      handle: '@${author['handle'] as String? ?? ''}',
      body: record['text'] as String? ?? '',
      timestamp: DateTime.tryParse(createdAt) ?? DateTime.now(),
      avatarUrl: author['avatar'] as String?,
      accountId: accountId,
    );
  }

  /// セッションをリフレッシュ
  Future<BlueskyCredentials> refreshSession(BlueskyCredentials creds) async {
    final uri = Uri.parse(
      '${creds.pdsUrl}/xrpc/com.atproto.server.refreshSession',
    );

    final response = await http.post(uri, headers: {
      'Authorization': 'Bearer ${creds.refreshJwt}',
      'Accept': 'application/json',
    });

    if (response.statusCode != 200) {
      throw BlueskyAuthException(
        'Failed to refresh session: ${response.statusCode}',
      );
    }

    final body = json.decode(response.body) as Map<String, dynamic>;

    debugPrint('[BlueskyApi] Session refreshed for ${creds.handle}');

    return creds.copyWith(
      accessJwt: body['accessJwt'] as String,
      refreshJwt: body['refreshJwt'] as String,
    );
  }

  /// タイムライン取得 (トークン期限切れ時は自動リフレッシュ)
  Future<({List<Post> posts, BlueskyCredentials? updatedCreds})>
      getTimelineWithRefresh(
    BlueskyCredentials creds, {
    String? accountId,
  }) async {
    try {
      final posts = await getTimeline(creds, accountId: accountId);
      return (posts: posts, updatedCreds: null);
    } on BlueskyAuthException {
      debugPrint('[BlueskyApi] Token expired, refreshing...');
      final newCreds = await refreshSession(creds);
      final posts = await getTimeline(newCreds, accountId: accountId);
      return (posts: posts, updatedCreds: newCreds);
    }
  }
}

class BlueskyApiException implements Exception {
  BlueskyApiException(this.message);
  final String message;
  @override
  String toString() => 'BlueskyApiException: $message';
}

class BlueskyAuthException implements Exception {
  BlueskyAuthException(this.message);
  final String message;
  @override
  String toString() => 'BlueskyAuthException: $message';
}
