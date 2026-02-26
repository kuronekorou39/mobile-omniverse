import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/models/post.dart';
import 'package:mobile_omniverse/models/sns_service.dart';

/// テスト用 Post ファクトリ
Post makePost({
  String id = 'x_123',
  SnsService source = SnsService.x,
  String username = 'Test User',
  String handle = '@testuser',
  String body = 'Hello, world!',
  DateTime? timestamp,
  String? avatarUrl,
  String? accountId,
  int likeCount = 0,
  int replyCount = 0,
  int repostCount = 0,
  bool isLiked = false,
  bool isReposted = false,
  List<String> imageUrls = const [],
  String? videoUrl,
  String? videoThumbnailUrl,
  String? permalink,
  String? inReplyToId,
  String? uri,
  String? cid,
  bool isRetweet = false,
  String? retweetedByUsername,
  String? retweetedByHandle,
  Post? quotedPost,
}) {
  return Post(
    id: id,
    source: source,
    username: username,
    handle: handle,
    body: body,
    timestamp: timestamp ?? DateTime(2024, 1, 15, 12, 0, 0),
    avatarUrl: avatarUrl,
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
    inReplyToId: inReplyToId,
    uri: uri,
    cid: cid,
    isRetweet: isRetweet,
    retweetedByUsername: retweetedByUsername,
    retweetedByHandle: retweetedByHandle,
    quotedPost: quotedPost,
  );
}

/// テスト用 Bluesky Post
Post makeBlueskyPost({
  String id = 'bsky_abc',
  String username = 'Bluesky User',
  String handle = '@bsky.test',
  String body = 'Hello from Bluesky!',
  DateTime? timestamp,
  String? uri = 'at://did:plc:test/app.bsky.feed.post/abc',
  String? cid = 'bafyreicid123',
}) {
  return makePost(
    id: id,
    source: SnsService.bluesky,
    username: username,
    handle: handle,
    body: body,
    timestamp: timestamp,
    uri: uri,
    cid: cid,
    permalink: 'https://bsky.app/profile/bsky.test/post/abc',
  );
}

/// テスト用 X Account
Account makeXAccount({
  String id = 'x_acc_1',
  String displayName = 'X User',
  String handle = '@xuser',
  String authToken = 'test_auth',
  String ct0 = 'test_ct0',
  bool isEnabled = true,
}) {
  return Account(
    id: id,
    service: SnsService.x,
    displayName: displayName,
    handle: handle,
    credentials: XCredentials(authToken: authToken, ct0: ct0),
    createdAt: DateTime(2024, 1, 1),
    isEnabled: isEnabled,
  );
}

/// テスト用 Bluesky Account
Account makeBlueskyAccount({
  String id = 'bsky_acc_1',
  String displayName = 'Bluesky User',
  String handle = '@bsky.test',
  String accessJwt = 'test_jwt',
  String refreshJwt = 'test_refresh',
  String did = 'did:plc:test123',
  bool isEnabled = true,
}) {
  return Account(
    id: id,
    service: SnsService.bluesky,
    displayName: displayName,
    handle: handle,
    credentials: BlueskyCredentials(
      accessJwt: accessJwt,
      refreshJwt: refreshJwt,
      did: did,
      handle: handle.replaceFirst('@', ''),
    ),
    createdAt: DateTime(2024, 1, 1),
    isEnabled: isEnabled,
  );
}

/// X API parseTweet 用のテストデータ (GraphQL レスポンス構造)
Map<String, dynamic> makeXTweetResult({
  String tweetId = '1234567890',
  String screenName = 'testuser',
  String name = 'Test User',
  String fullText = 'Hello, world!',
  String createdAt = 'Mon Jan 15 12:00:00 +0000 2024',
  int favoriteCount = 10,
  int retweetCount = 5,
  int replyCount = 2,
  bool favorited = false,
  bool retweeted = false,
  String? profileImageUrl,
  List<Map<String, dynamic>>? media,
  Map<String, dynamic>? retweetedStatusResult,
  Map<String, dynamic>? quotedStatusResult,
  List<Map<String, dynamic>>? urls,
}) {
  return {
    '__typename': 'Tweet',
    'legacy': {
      'id_str': tweetId,
      'full_text': fullText,
      'created_at': createdAt,
      'favorite_count': favoriteCount,
      'retweet_count': retweetCount,
      'reply_count': replyCount,
      'favorited': favorited,
      'retweeted': retweeted,
      if (retweetedStatusResult != null)
        'retweeted_status_result': retweetedStatusResult,
      if (media != null)
        'extended_entities': {'media': media},
      'entities': {
        if (urls != null) 'urls': urls,
      },
    },
    'core': {
      'user_results': {
        'result': {
          'legacy': {
            'name': name,
            'screen_name': screenName,
            'profile_image_url_https': profileImageUrl ?? 'https://pbs.twimg.com/default.jpg',
          },
        },
      },
    },
    if (quotedStatusResult != null)
      'quoted_status_result': quotedStatusResult,
  };
}

/// X API タイムラインレスポンスのテストデータ
Map<String, dynamic> makeXTimelineResponse(List<Map<String, dynamic>> tweets) {
  return {
    'data': {
      'home': {
        'home_timeline_urt': {
          'instructions': [
            {
              'type': 'TimelineAddEntries',
              'entries': tweets.asMap().entries.map((e) {
                return {
                  'entryId': 'tweet-${e.key}',
                  'content': {
                    'entryType': 'TimelineTimelineItem',
                    'itemContent': {
                      'tweet_results': {
                        'result': e.value,
                      },
                    },
                  },
                };
              }).toList(),
            },
          ],
        },
      },
    },
  };
}

/// Bluesky post オブジェクトのテストデータ
Map<String, dynamic> makeBlueskyPostObject({
  String did = 'did:plc:test',
  String handle = 'test.bsky.social',
  String displayName = 'Test User',
  String text = 'Hello from Bluesky!',
  String? createdAt,
  String? atUri,
  String postCid = 'bafyreicid123',
  int likeCount = 3,
  int replyCount = 1,
  int repostCount = 2,
  String? likeUri,
  String? repostUri,
  Map<String, dynamic>? embed,
}) {
  final rkey = (atUri ?? 'at://$did/app.bsky.feed.post/abc123').split('/').last;
  return {
    'uri': atUri ?? 'at://$did/app.bsky.feed.post/$rkey',
    'cid': postCid,
    'author': {
      'did': did,
      'handle': handle,
      'displayName': displayName,
      'avatar': 'https://cdn.bsky.app/avatar.jpg',
    },
    'record': <String, dynamic>{
      '\$type': 'app.bsky.feed.post',
      'text': text,
      'createdAt': createdAt ?? '2024-01-15T12:00:00.000Z',
    },
    'likeCount': likeCount,
    'replyCount': replyCount,
    'repostCount': repostCount,
    'viewer': {
      if (likeUri != null) 'like': likeUri,
      if (repostUri != null) 'repost': repostUri,
    },
    if (embed != null) 'embed': embed,
  };
}
