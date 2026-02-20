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
    String? cursor,
  }) async {
    var url = '${creds.pdsUrl}/xrpc/app.bsky.feed.getTimeline?limit=$limit';
    if (cursor != null) url += '&cursor=${Uri.encodeComponent(cursor)}';

    final uri = Uri.parse(url);

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

  /// 投稿スレッド取得
  Future<List<Post>> getPostThread(
    BlueskyCredentials creds,
    String postUri, {
    String? accountId,
  }) async {
    final uri = Uri.parse(
      '${creds.pdsUrl}/xrpc/app.bsky.feed.getPostThread'
      '?uri=${Uri.encodeComponent(postUri)}&depth=10',
    );

    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer ${creds.accessJwt}',
      'Accept': 'application/json',
    });

    if (response.statusCode == 401) {
      throw BlueskyAuthException('Token expired');
    }

    if (response.statusCode != 200) {
      throw BlueskyApiException(
        'Failed to fetch thread: ${response.statusCode}',
      );
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    final thread = body['thread'] as Map<String, dynamic>?;
    if (thread == null) return [];

    final posts = <Post>[];
    _flattenThread(thread, posts, accountId);
    return posts;
  }

  void _flattenThread(
      Map<String, dynamic> thread, List<Post> posts, String? accountId) {
    // Parent chain
    final parent = thread['parent'] as Map<String, dynamic>?;
    if (parent != null && parent['\$type'] == 'app.bsky.feed.defs#threadViewPost') {
      _flattenThread(parent, posts, accountId);
    }

    // Current post
    final post = thread['post'] as Map<String, dynamic>?;
    if (post != null) {
      posts.add(_parsePostObject(post, accountId));
    }

    // Replies
    final replies = thread['replies'] as List<dynamic>?;
    if (replies != null) {
      for (final reply in replies) {
        final replyMap = reply as Map<String, dynamic>;
        if (replyMap['\$type'] == 'app.bsky.feed.defs#threadViewPost') {
          final replyPost = replyMap['post'] as Map<String, dynamic>?;
          if (replyPost != null) {
            posts.add(_parsePostObject(replyPost, accountId));
          }
        }
      }
    }
  }

  /// いいね
  Future<String?> likePost(
    BlueskyCredentials creds,
    String postUri,
    String postCid,
  ) async {
    final uri = Uri.parse(
      '${creds.pdsUrl}/xrpc/com.atproto.repo.createRecord',
    );
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${creds.accessJwt}',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'repo': creds.did,
        'collection': 'app.bsky.feed.like',
        'record': {
          '\$type': 'app.bsky.feed.like',
          'subject': {'uri': postUri, 'cid': postCid},
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      }),
    );
    if (response.statusCode == 200) {
      final body = json.decode(response.body) as Map<String, dynamic>;
      return body['uri'] as String?;
    }
    return null;
  }

  /// いいね解除
  Future<bool> unlikePost(BlueskyCredentials creds, String likeUri) async {
    final rkey = likeUri.split('/').last;
    final uri = Uri.parse(
      '${creds.pdsUrl}/xrpc/com.atproto.repo.deleteRecord',
    );
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${creds.accessJwt}',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'repo': creds.did,
        'collection': 'app.bsky.feed.like',
        'rkey': rkey,
      }),
    );
    return response.statusCode == 200;
  }

  /// リポスト
  Future<String?> repost(
    BlueskyCredentials creds,
    String postUri,
    String postCid,
  ) async {
    final uri = Uri.parse(
      '${creds.pdsUrl}/xrpc/com.atproto.repo.createRecord',
    );
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${creds.accessJwt}',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'repo': creds.did,
        'collection': 'app.bsky.feed.repost',
        'record': {
          '\$type': 'app.bsky.feed.repost',
          'subject': {'uri': postUri, 'cid': postCid},
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      }),
    );
    if (response.statusCode == 200) {
      final body = json.decode(response.body) as Map<String, dynamic>;
      return body['uri'] as String?;
    }
    return null;
  }

  /// リポスト解除
  Future<bool> unrepost(BlueskyCredentials creds, String repostUri) async {
    final rkey = repostUri.split('/').last;
    final uri = Uri.parse(
      '${creds.pdsUrl}/xrpc/com.atproto.repo.deleteRecord',
    );
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${creds.accessJwt}',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'repo': creds.did,
        'collection': 'app.bsky.feed.repost',
        'rkey': rkey,
      }),
    );
    return response.statusCode == 200;
  }

  Post _parsePost(dynamic item, String? accountId) {
    final feedItem = item as Map<String, dynamic>;
    final post = feedItem['post'] as Map<String, dynamic>;
    return _parsePostObject(post, accountId);
  }

  Post _parsePostObject(Map<String, dynamic> post, String? accountId) {
    final author = post['author'] as Map<String, dynamic>;
    final record = post['record'] as Map<String, dynamic>;

    final atUri = post['uri'] as String? ?? '';
    final postCid = post['cid'] as String? ?? '';
    // AT URI format: at://did/app.bsky.feed.post/rkey
    final postId = atUri.isNotEmpty ? atUri.split('/').last : '${post.hashCode}';

    final createdAt = record['createdAt'] as String? ?? '';

    // Engagement counts
    final likeCount = post['likeCount'] as int? ?? 0;
    final replyCount = post['replyCount'] as int? ?? 0;
    final repostCount = post['repostCount'] as int? ?? 0;

    // Viewer state
    final viewer = post['viewer'] as Map<String, dynamic>? ?? {};
    final isLiked = viewer['like'] != null;
    final isReposted = viewer['repost'] != null;

    // Reply info
    final replyRef = record['reply'] as Map<String, dynamic>?;
    final inReplyToUri = replyRef?['parent']?['uri'] as String?;

    // Media extraction from embed
    final imageUrls = <String>[];
    String? videoUrl;
    String? videoThumbnailUrl;

    final embed = post['embed'] as Map<String, dynamic>?;
    if (embed != null) {
      _extractMedia(embed, imageUrls, (v, t) {
        videoUrl = v;
        videoThumbnailUrl = t;
      });
    }

    // Permalink
    final handle = author['handle'] as String? ?? '';
    final permalink = handle.isNotEmpty && postId.isNotEmpty
        ? 'https://bsky.app/profile/$handle/post/$postId'
        : null;

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
      likeCount: likeCount,
      replyCount: replyCount,
      repostCount: repostCount,
      isLiked: isLiked,
      isReposted: isReposted,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      videoThumbnailUrl: videoThumbnailUrl,
      permalink: permalink,
      inReplyToId: inReplyToUri,
      uri: atUri,
      cid: postCid,
    );
  }

  void _extractMedia(
    Map<String, dynamic> embed,
    List<String> imageUrls,
    void Function(String? videoUrl, String? thumbnail) onVideo,
  ) {
    final type = embed['\$type'] as String?;

    if (type == 'app.bsky.embed.images#view') {
      final images = embed['images'] as List<dynamic>? ?? [];
      for (final img in images) {
        final m = img as Map<String, dynamic>;
        final fullsize = m['fullsize'] as String?;
        final thumb = m['thumb'] as String?;
        if (fullsize != null) {
          imageUrls.add(fullsize);
        } else if (thumb != null) {
          imageUrls.add(thumb);
        }
      }
    } else if (type == 'app.bsky.embed.video#view') {
      final playlist = embed['playlist'] as String?;
      final thumbnail = embed['thumbnail'] as String?;
      onVideo(playlist, thumbnail);
    } else if (type == 'app.bsky.embed.recordWithMedia#view') {
      // Embed with media (quote + media)
      final media = embed['media'] as Map<String, dynamic>?;
      if (media != null) {
        _extractMedia(media, imageUrls, onVideo);
      }
    } else if (type == 'app.bsky.embed.external#view') {
      // External link with thumbnail
      final external_ = embed['external'] as Map<String, dynamic>?;
      final thumb = external_?['thumb'] as String?;
      if (thumb != null) imageUrls.add(thumb);
    }
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
    String? cursor,
  }) async {
    try {
      final posts = await getTimeline(creds, accountId: accountId, cursor: cursor);
      return (posts: posts, updatedCreds: null);
    } on BlueskyAuthException {
      debugPrint('[BlueskyApi] Token expired, refreshing...');
      final newCreds = await refreshSession(creds);
      final posts = await getTimeline(newCreds, accountId: accountId, cursor: cursor);
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
