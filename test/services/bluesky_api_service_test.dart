import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/models/post.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/bluesky_api_service.dart';

import '../helpers/mock_http_client.dart';
import '../helpers/test_data.dart';

void main() {
  final service = BlueskyApiService.instance;

  setUp(() {
    registerHttpFallbacks();
  });

  tearDown(() {
    service.httpClientOverride = null;
  });

  group('parsePostObject', () {
    test('basic post parsing', () {
      final postObj = makeBlueskyPostObject(
        did: 'did:plc:user1',
        handle: 'alice.bsky.social',
        displayName: 'Alice',
        text: 'Hello Bluesky!',
        createdAt: '2024-06-15T10:30:00.000Z',
        atUri: 'at://did:plc:user1/app.bsky.feed.post/rkey1',
        postCid: 'bafycid1',
      );

      final post = service.parsePostObject(postObj, 'acc1');

      expect(post.id, 'bsky_rkey1');
      expect(post.source, SnsService.bluesky);
      expect(post.username, 'Alice');
      expect(post.handle, '@alice.bsky.social');
      expect(post.body, 'Hello Bluesky!');
      expect(post.timestamp, DateTime.parse('2024-06-15T10:30:00.000Z'));
      expect(post.accountId, 'acc1');
      expect(post.uri, 'at://did:plc:user1/app.bsky.feed.post/rkey1');
      expect(post.cid, 'bafycid1');
      expect(
          post.permalink, 'https://bsky.app/profile/alice.bsky.social/post/rkey1');
    });

    test('engagement counts are parsed', () {
      final postObj = makeBlueskyPostObject(
        likeCount: 42,
        replyCount: 7,
        repostCount: 13,
      );

      final post = service.parsePostObject(postObj, null);

      expect(post.likeCount, 42);
      expect(post.replyCount, 7);
      expect(post.repostCount, 13);
    });

    test('viewer state isLiked when like uri present', () {
      final postObj = makeBlueskyPostObject(
        likeUri: 'at://did:plc:me/app.bsky.feed.like/abc',
      );

      final post = service.parsePostObject(postObj, null);

      expect(post.isLiked, true);
      expect(post.isReposted, false);
    });

    test('viewer state isReposted when repost uri present', () {
      final postObj = makeBlueskyPostObject(
        repostUri: 'at://did:plc:me/app.bsky.feed.repost/xyz',
      );

      final post = service.parsePostObject(postObj, null);

      expect(post.isLiked, false);
      expect(post.isReposted, true);
    });

    test('viewer state both liked and reposted', () {
      final postObj = makeBlueskyPostObject(
        likeUri: 'at://did:plc:me/app.bsky.feed.like/abc',
        repostUri: 'at://did:plc:me/app.bsky.feed.repost/xyz',
      );

      final post = service.parsePostObject(postObj, null);

      expect(post.isLiked, true);
      expect(post.isReposted, true);
    });

    test('reply info from record reply field', () {
      final postObj = makeBlueskyPostObject();
      // Inject reply info into record
      (postObj['record'] as Map<String, dynamic>)['reply'] = <String, dynamic>{
        'parent': <String, dynamic>{
          'uri': 'at://did:plc:parent/app.bsky.feed.post/parentrkey',
          'cid': 'parentcid',
        },
        'root': <String, dynamic>{
          'uri': 'at://did:plc:root/app.bsky.feed.post/rootrkey',
          'cid': 'rootcid',
        },
      };

      final post = service.parsePostObject(postObj, null);

      expect(post.inReplyToId,
          'at://did:plc:parent/app.bsky.feed.post/parentrkey');
    });

    test('embed with images extracts image URLs', () {
      final postObj = makeBlueskyPostObject(
        embed: {
          '\$type': 'app.bsky.embed.images#view',
          'images': [
            {
              'fullsize': 'https://cdn.bsky.app/img/feed/full1.jpg',
              'thumb': 'https://cdn.bsky.app/img/feed/thumb1.jpg',
              'alt': 'Image 1',
            },
            {
              'fullsize': 'https://cdn.bsky.app/img/feed/full2.jpg',
              'thumb': 'https://cdn.bsky.app/img/feed/thumb2.jpg',
              'alt': 'Image 2',
            },
          ],
        },
      );

      final post = service.parsePostObject(postObj, null);

      expect(post.imageUrls, hasLength(2));
      expect(post.imageUrls[0], 'https://cdn.bsky.app/img/feed/full1.jpg');
      expect(post.imageUrls[1], 'https://cdn.bsky.app/img/feed/full2.jpg');
    });

    test('AT URI extraction for postId', () {
      final postObj = makeBlueskyPostObject(
        atUri: 'at://did:plc:xyz/app.bsky.feed.post/mypostkey',
      );

      final post = service.parsePostObject(postObj, null);

      expect(post.id, 'bsky_mypostkey');
    });

    test('missing displayName falls back to handle', () {
      final postObj = makeBlueskyPostObject(
        handle: 'fallback.bsky.social',
      );
      // Remove displayName
      (postObj['author'] as Map<String, dynamic>).remove('displayName');

      final post = service.parsePostObject(postObj, null);

      expect(post.username, 'fallback.bsky.social');
    });

    test('avatarUrl is extracted from author', () {
      final postObj = makeBlueskyPostObject();

      final post = service.parsePostObject(postObj, null);

      expect(post.avatarUrl, 'https://cdn.bsky.app/avatar.jpg');
    });
  });

  group('parsePost', () {
    test('repost detection via reason field', () {
      final feedItem = {
        'post': makeBlueskyPostObject(
          handle: 'original.bsky.social',
          displayName: 'Original Author',
          text: 'Original post',
        ),
        'reason': {
          '\$type': 'app.bsky.feed.defs#reasonRepost',
          'by': {
            'did': 'did:plc:reposter',
            'handle': 'reposter.bsky.social',
            'displayName': 'Reposter',
          },
          'indexedAt': '2024-06-15T12:00:00.000Z',
        },
      };

      final post = service.parsePost(feedItem, null);

      expect(post.isRetweet, true);
      expect(post.retweetedByUsername, 'Reposter');
      expect(post.retweetedByHandle, '@reposter.bsky.social');
      // Original content should be preserved
      expect(post.username, 'Original Author');
      expect(post.body, 'Original post');
    });

    test('normal post without reason is not a repost', () {
      final feedItem = {
        'post': makeBlueskyPostObject(
          handle: 'poster.bsky.social',
          displayName: 'Poster',
          text: 'Normal post',
        ),
      };

      final post = service.parsePost(feedItem, 'acc1');

      expect(post.isRetweet, false);
      expect(post.retweetedByUsername, isNull);
      expect(post.retweetedByHandle, isNull);
      expect(post.accountId, 'acc1');
    });

    test('reason without displayName falls back to handle', () {
      final feedItem = {
        'post': makeBlueskyPostObject(),
        'reason': {
          '\$type': 'app.bsky.feed.defs#reasonRepost',
          'by': {
            'did': 'did:plc:reposter',
            'handle': 'reposter.bsky.social',
          },
        },
      };

      final post = service.parsePost(feedItem, null);

      expect(post.isRetweet, true);
      expect(post.retweetedByUsername, 'reposter.bsky.social');
    });
  });

  group('flattenThread', () {
    test('parent chain recursion places parent before current', () {
      final thread = {
        '\$type': 'app.bsky.feed.defs#threadViewPost',
        'parent': {
          '\$type': 'app.bsky.feed.defs#threadViewPost',
          'post': makeBlueskyPostObject(
            text: 'Parent post',
            atUri: 'at://did:plc:test/app.bsky.feed.post/parent1',
          ),
        },
        'post': makeBlueskyPostObject(
          text: 'Current post',
          atUri: 'at://did:plc:test/app.bsky.feed.post/current1',
        ),
      };

      final posts = <Post>[];
      service.flattenThread(thread, posts, null);

      expect(posts, hasLength(2));
      expect(posts[0].body, 'Parent post');
      expect(posts[1].body, 'Current post');
    });

    test('replies are added after current post', () {
      final thread = {
        '\$type': 'app.bsky.feed.defs#threadViewPost',
        'post': makeBlueskyPostObject(
          text: 'Main post',
          atUri: 'at://did:plc:test/app.bsky.feed.post/main1',
        ),
        'replies': [
          {
            '\$type': 'app.bsky.feed.defs#threadViewPost',
            'post': makeBlueskyPostObject(
              text: 'Reply 1',
              atUri: 'at://did:plc:test/app.bsky.feed.post/reply1',
            ),
          },
          {
            '\$type': 'app.bsky.feed.defs#threadViewPost',
            'post': makeBlueskyPostObject(
              text: 'Reply 2',
              atUri: 'at://did:plc:test/app.bsky.feed.post/reply2',
            ),
          },
        ],
      };

      final posts = <Post>[];
      service.flattenThread(thread, posts, null);

      expect(posts, hasLength(3));
      expect(posts[0].body, 'Main post');
      expect(posts[1].body, 'Reply 1');
      expect(posts[2].body, 'Reply 2');
    });

    test('non-threadViewPost types in replies are skipped', () {
      final thread = {
        '\$type': 'app.bsky.feed.defs#threadViewPost',
        'post': makeBlueskyPostObject(
          text: 'Main',
          atUri: 'at://did:plc:test/app.bsky.feed.post/main2',
        ),
        'replies': [
          {
            '\$type': 'app.bsky.feed.defs#threadViewPost',
            'post': makeBlueskyPostObject(
              text: 'Valid reply',
              atUri: 'at://did:plc:test/app.bsky.feed.post/validreply',
            ),
          },
          {
            '\$type': 'app.bsky.feed.defs#blockedPost',
            'uri': 'at://did:plc:blocked/app.bsky.feed.post/blocked1',
          },
        ],
      };

      final posts = <Post>[];
      service.flattenThread(thread, posts, null);

      expect(posts, hasLength(2));
      expect(posts[0].body, 'Main');
      expect(posts[1].body, 'Valid reply');
    });

    test('non-threadViewPost parent is not recursed', () {
      final thread = {
        '\$type': 'app.bsky.feed.defs#threadViewPost',
        'parent': {
          '\$type': 'app.bsky.feed.defs#notFoundPost',
          'uri': 'at://did:plc:test/app.bsky.feed.post/deleted',
        },
        'post': makeBlueskyPostObject(
          text: 'Orphan post',
          atUri: 'at://did:plc:test/app.bsky.feed.post/orphan1',
        ),
      };

      final posts = <Post>[];
      service.flattenThread(thread, posts, null);

      expect(posts, hasLength(1));
      expect(posts[0].body, 'Orphan post');
    });

    test('deep parent chain is fully traversed', () {
      final thread = {
        '\$type': 'app.bsky.feed.defs#threadViewPost',
        'parent': {
          '\$type': 'app.bsky.feed.defs#threadViewPost',
          'parent': {
            '\$type': 'app.bsky.feed.defs#threadViewPost',
            'post': makeBlueskyPostObject(
              text: 'Grandparent',
              atUri: 'at://did:plc:test/app.bsky.feed.post/gp1',
            ),
          },
          'post': makeBlueskyPostObject(
            text: 'Parent',
            atUri: 'at://did:plc:test/app.bsky.feed.post/p1',
          ),
        },
        'post': makeBlueskyPostObject(
          text: 'Child',
          atUri: 'at://did:plc:test/app.bsky.feed.post/c1',
        ),
      };

      final posts = <Post>[];
      service.flattenThread(thread, posts, null);

      expect(posts, hasLength(3));
      expect(posts[0].body, 'Grandparent');
      expect(posts[1].body, 'Parent');
      expect(posts[2].body, 'Child');
    });
  });

  group('extractMedia', () {
    test('images#view extracts fullsize URLs', () {
      final embed = {
        '\$type': 'app.bsky.embed.images#view',
        'images': [
          {
            'fullsize': 'https://cdn.bsky.app/img/full1.jpg',
            'thumb': 'https://cdn.bsky.app/img/thumb1.jpg',
          },
        ],
      };

      final imageUrls = <String>[];
      String? videoUrl;
      String? videoThumb;
      service.extractMedia(embed, imageUrls, (v, t) {
        videoUrl = v;
        videoThumb = t;
      });

      expect(imageUrls, hasLength(1));
      expect(imageUrls[0], 'https://cdn.bsky.app/img/full1.jpg');
      expect(videoUrl, isNull);
      expect(videoThumb, isNull);
    });

    test('images#view falls back to thumb when no fullsize', () {
      final embed = {
        '\$type': 'app.bsky.embed.images#view',
        'images': [
          {
            'thumb': 'https://cdn.bsky.app/img/thumb_only.jpg',
          },
        ],
      };

      final imageUrls = <String>[];
      service.extractMedia(embed, imageUrls, (v, t) {});

      expect(imageUrls, hasLength(1));
      expect(imageUrls[0], 'https://cdn.bsky.app/img/thumb_only.jpg');
    });

    test('video#view extracts playlist and thumbnail', () {
      final embed = {
        '\$type': 'app.bsky.embed.video#view',
        'playlist': 'https://video.bsky.app/watch/playlist.m3u8',
        'thumbnail': 'https://video.bsky.app/watch/thumb.jpg',
      };

      final imageUrls = <String>[];
      String? videoUrl;
      String? videoThumb;
      service.extractMedia(embed, imageUrls, (v, t) {
        videoUrl = v;
        videoThumb = t;
      });

      expect(imageUrls, isEmpty);
      expect(videoUrl, 'https://video.bsky.app/watch/playlist.m3u8');
      expect(videoThumb, 'https://video.bsky.app/watch/thumb.jpg');
    });

    test('recordWithMedia#view extracts media from nested media field', () {
      final embed = {
        '\$type': 'app.bsky.embed.recordWithMedia#view',
        'record': {
          'record': {
            '\$type': 'app.bsky.embed.record#viewRecord',
          },
        },
        'media': {
          '\$type': 'app.bsky.embed.images#view',
          'images': [
            {
              'fullsize': 'https://cdn.bsky.app/img/nested.jpg',
              'thumb': 'https://cdn.bsky.app/img/nested_thumb.jpg',
            },
          ],
        },
      };

      final imageUrls = <String>[];
      service.extractMedia(embed, imageUrls, (v, t) {});

      expect(imageUrls, hasLength(1));
      expect(imageUrls[0], 'https://cdn.bsky.app/img/nested.jpg');
    });

    test('external#view extracts thumbnail', () {
      final embed = {
        '\$type': 'app.bsky.embed.external#view',
        'external': {
          'uri': 'https://example.com/article',
          'title': 'Article Title',
          'description': 'Article description',
          'thumb': 'https://cdn.bsky.app/img/external_thumb.jpg',
        },
      };

      final imageUrls = <String>[];
      service.extractMedia(embed, imageUrls, (v, t) {});

      expect(imageUrls, hasLength(1));
      expect(imageUrls[0], 'https://cdn.bsky.app/img/external_thumb.jpg');
    });

    test('unknown embed type extracts nothing', () {
      final embed = {
        '\$type': 'app.bsky.embed.unknown#view',
      };

      final imageUrls = <String>[];
      String? videoUrl;
      service.extractMedia(embed, imageUrls, (v, t) {
        videoUrl = v;
      });

      expect(imageUrls, isEmpty);
      expect(videoUrl, isNull);
    });
  });

  group('extractQuotedPost', () {
    test('record#view extracts quoted post', () {
      final embed = {
        '\$type': 'app.bsky.embed.record#view',
        'record': {
          '\$type': 'app.bsky.embed.record#viewRecord',
          'uri': 'at://did:plc:quoted/app.bsky.feed.post/qrkey',
          'cid': 'bafyquoted',
          'author': {
            'did': 'did:plc:quoted',
            'handle': 'quoted.bsky.social',
            'displayName': 'Quoted Author',
            'avatar': 'https://cdn.bsky.app/avatar_q.jpg',
          },
          'value': {
            'text': 'Quoted text',
            'createdAt': '2024-06-14T09:00:00.000Z',
          },
        },
      };

      final quoted = service.extractQuotedPost(embed, 'acc1');

      expect(quoted, isNotNull);
      expect(quoted!.id, 'bsky_qrkey');
      expect(quoted.username, 'Quoted Author');
      expect(quoted.handle, '@quoted.bsky.social');
      expect(quoted.body, 'Quoted text');
      expect(quoted.uri, 'at://did:plc:quoted/app.bsky.feed.post/qrkey');
      expect(quoted.cid, 'bafyquoted');
      expect(quoted.permalink,
          'https://bsky.app/profile/quoted.bsky.social/post/qrkey');
    });

    test('recordWithMedia#view extracts quoted post from nested record', () {
      final embed = {
        '\$type': 'app.bsky.embed.recordWithMedia#view',
        'record': {
          'record': {
            '\$type': 'app.bsky.embed.record#viewRecord',
            'uri': 'at://did:plc:nested/app.bsky.feed.post/nrkey',
            'cid': 'bafynested',
            'author': {
              'did': 'did:plc:nested',
              'handle': 'nested.bsky.social',
              'displayName': 'Nested Author',
            },
            'value': {
              'text': 'Nested quoted text',
              'createdAt': '2024-06-13T08:00:00.000Z',
            },
          },
        },
        'media': {
          '\$type': 'app.bsky.embed.images#view',
          'images': [],
        },
      };

      final quoted = service.extractQuotedPost(embed, null);

      expect(quoted, isNotNull);
      expect(quoted!.id, 'bsky_nrkey');
      expect(quoted.body, 'Nested quoted text');
    });

    test('viewRecord type check - blocked post is skipped', () {
      final embed = {
        '\$type': 'app.bsky.embed.record#view',
        'record': {
          '\$type': 'app.bsky.embed.record#viewBlocked',
          'uri': 'at://did:plc:blocked/app.bsky.feed.post/blk',
        },
      };

      final quoted = service.extractQuotedPost(embed, null);
      expect(quoted, isNull);
    });

    test('notFound post is skipped', () {
      final embed = {
        '\$type': 'app.bsky.embed.record#view',
        'record': {
          '\$type': 'app.bsky.embed.record#viewNotFound',
          'uri': 'at://did:plc:missing/app.bsky.feed.post/nf',
        },
      };

      final quoted = service.extractQuotedPost(embed, null);
      expect(quoted, isNull);
    });

    test('null record returns null', () {
      final embed = {
        '\$type': 'app.bsky.embed.images#view',
        'images': [],
      };

      final quoted = service.extractQuotedPost(embed, null);
      expect(quoted, isNull);
    });

    test('quoted post with embeds extracts media', () {
      final embed = {
        '\$type': 'app.bsky.embed.record#view',
        'record': {
          '\$type': 'app.bsky.embed.record#viewRecord',
          'uri': 'at://did:plc:qmedia/app.bsky.feed.post/qm1',
          'cid': 'bafyqmedia',
          'author': {
            'did': 'did:plc:qmedia',
            'handle': 'media.bsky.social',
            'displayName': 'Media Author',
          },
          'value': {
            'text': 'Post with media',
            'createdAt': '2024-06-12T07:00:00.000Z',
          },
          'embeds': [
            {
              '\$type': 'app.bsky.embed.images#view',
              'images': [
                {
                  'fullsize': 'https://cdn.bsky.app/img/quoted_img.jpg',
                  'thumb': 'https://cdn.bsky.app/img/quoted_thumb.jpg',
                },
              ],
            },
          ],
        },
      };

      final quoted = service.extractQuotedPost(embed, null);

      expect(quoted, isNotNull);
      expect(quoted!.imageUrls, hasLength(1));
      expect(quoted.imageUrls[0], 'https://cdn.bsky.app/img/quoted_img.jpg');
    });
  });

  // ===== HTTP-level tests =====

  BlueskyCredentials makeBskyCreds() => BlueskyCredentials(
        accessJwt: 'test_jwt',
        refreshJwt: 'test_refresh',
        did: 'did:plc:test',
        handle: 'test.bsky.social',
      );

  Map<String, dynamic> makeBskyFeedResponse(
      [List<Map<String, dynamic>>? posts]) {
    return {
      'feed': (posts ?? [makeBlueskyPostObject()]).map((p) => {'post': p}).toList(),
    };
  }

  group('getTimeline (HTTP)', () {
    test('returns posts on 200', () async {
      final creds = makeBskyCreds();
      final feedJson = makeBskyFeedResponse();
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode(feedJson),
      );
      service.httpClientOverride = client;

      final result = await service.getTimeline(creds);
      expect(result.posts, isNotEmpty);
      expect(result.posts.first.source, SnsService.bluesky);
    });

    test('throws BlueskyAuthException on 401', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 401, body: '{}');
      service.httpClientOverride = client;

      expect(
        () => service.getTimeline(creds),
        throwsA(isA<BlueskyAuthException>()),
      );
    });

    test('throws BlueskyAuthException on 400 with ExpiredToken', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(
        statusCode: 400,
        body: jsonEncode({'error': 'ExpiredToken'}),
      );
      service.httpClientOverride = client;

      expect(
        () => service.getTimeline(creds),
        throwsA(isA<BlueskyAuthException>()),
      );
    });

    test('throws BlueskyAuthException on 400 with InvalidToken', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(
        statusCode: 400,
        body: jsonEncode({'error': 'InvalidToken'}),
      );
      service.httpClientOverride = client;

      expect(
        () => service.getTimeline(creds),
        throwsA(isA<BlueskyAuthException>()),
      );
    });

    test('throws BlueskyApiException on 400 with other error', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(
        statusCode: 400,
        body: jsonEncode({'error': 'SomeOtherError'}),
      );
      service.httpClientOverride = client;

      expect(
        () => service.getTimeline(creds),
        throwsA(isA<BlueskyApiException>()),
      );
    });

    test('throws BlueskyApiException on 500', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 500, body: '{}');
      service.httpClientOverride = client;

      expect(
        () => service.getTimeline(creds),
        throwsA(isA<BlueskyApiException>()),
      );
    });

    test('passes cursor parameter', () async {
      final creds = makeBskyCreds();
      final feedJson = makeBskyFeedResponse();
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode(feedJson),
      );
      service.httpClientOverride = client;

      final result = await service.getTimeline(creds, cursor: 'abc123');
      expect(result.posts, isNotEmpty);
    });

    test('empty feed returns empty list', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({'feed': []}),
      );
      service.httpClientOverride = client;

      final result = await service.getTimeline(creds);
      expect(result.posts, isEmpty);
    });
  });

  group('getPostThread (HTTP)', () {
    test('returns posts on 200', () async {
      final creds = makeBskyCreds();
      final threadJson = {
        'thread': {
          '\$type': 'app.bsky.feed.defs#threadViewPost',
          'post': makeBlueskyPostObject(text: 'Thread post'),
        },
      };
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode(threadJson),
      );
      service.httpClientOverride = client;

      final posts = await service.getPostThread(
        creds,
        'at://did:plc:test/app.bsky.feed.post/abc',
      );
      expect(posts, isNotEmpty);
      expect(posts.first.body, 'Thread post');
    });

    test('throws BlueskyAuthException on 401', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 401, body: '{}');
      service.httpClientOverride = client;

      expect(
        () => service.getPostThread(creds, 'at://did/post/abc'),
        throwsA(isA<BlueskyAuthException>()),
      );
    });

    test('throws BlueskyApiException on 500', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 500, body: '{}');
      service.httpClientOverride = client;

      expect(
        () => service.getPostThread(creds, 'at://did/post/abc'),
        throwsA(isA<BlueskyApiException>()),
      );
    });

    test('null thread returns empty list', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({'thread': null}),
      );
      service.httpClientOverride = client;

      final posts = await service.getPostThread(creds, 'at://did/post/abc');
      expect(posts, isEmpty);
    });
  });

  group('likePost (HTTP)', () {
    test('returns uri string on 200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({
          'uri': 'at://did:plc:test/app.bsky.feed.like/likekey',
          'cid': 'bafylike',
        }),
      );
      service.httpClientOverride = client;

      final uri = await service.likePost(creds, 'at://post/uri', 'postcid');
      expect(uri, 'at://did:plc:test/app.bsky.feed.like/likekey');
    });

    test('returns null on non-200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 400, body: '{}');
      service.httpClientOverride = client;

      final uri = await service.likePost(creds, 'at://post/uri', 'postcid');
      expect(uri, isNull);
    });
  });

  group('unlikePost (HTTP)', () {
    test('returns true on 200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 200, body: '{}');
      service.httpClientOverride = client;

      final result = await service.unlikePost(
        creds,
        'at://did:plc:test/app.bsky.feed.like/likekey',
      );
      expect(result, isTrue);
    });

    test('returns false on non-200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 500, body: '{}');
      service.httpClientOverride = client;

      final result = await service.unlikePost(
        creds,
        'at://did:plc:test/app.bsky.feed.like/likekey',
      );
      expect(result, isFalse);
    });
  });

  group('repost (HTTP)', () {
    test('returns uri string on 200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({
          'uri': 'at://did:plc:test/app.bsky.feed.repost/repostkey',
          'cid': 'bafyrepost',
        }),
      );
      service.httpClientOverride = client;

      final uri = await service.repost(creds, 'at://post/uri', 'postcid');
      expect(uri, 'at://did:plc:test/app.bsky.feed.repost/repostkey');
    });

    test('returns null on non-200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 400, body: '{}');
      service.httpClientOverride = client;

      final uri = await service.repost(creds, 'at://post/uri', 'postcid');
      expect(uri, isNull);
    });
  });

  group('unrepost (HTTP)', () {
    test('returns true on 200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 200, body: '{}');
      service.httpClientOverride = client;

      final result = await service.unrepost(
        creds,
        'at://did:plc:test/app.bsky.feed.repost/repostkey',
      );
      expect(result, isTrue);
    });

    test('returns false on non-200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 500, body: '{}');
      service.httpClientOverride = client;

      final result = await service.unrepost(
        creds,
        'at://did:plc:test/app.bsky.feed.repost/repostkey',
      );
      expect(result, isFalse);
    });
  });

  group('createPost (HTTP)', () {
    test('returns true on 200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({'uri': 'at://did:plc:test/app.bsky.feed.post/new'}),
      );
      service.httpClientOverride = client;

      final result = await service.createPost(creds, 'Hello from test');
      expect(result, isTrue);
    });

    test('returns false on non-200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 500, body: '{}');
      service.httpClientOverride = client;

      final result = await service.createPost(creds, 'Hello from test');
      expect(result, isFalse);
    });
  });

  group('getProfile (HTTP)', () {
    test('returns profile map on 200', () async {
      final creds = makeBskyCreds();
      final profileJson = {
        'did': 'did:plc:test',
        'handle': 'test.bsky.social',
        'displayName': 'Test User',
        'followersCount': 100,
        'followsCount': 50,
      };
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode(profileJson),
      );
      service.httpClientOverride = client;

      final profile = await service.getProfile(creds, 'test.bsky.social');
      expect(profile, isNotNull);
      expect(profile!['displayName'], 'Test User');
      expect(profile['followersCount'], 100);
    });

    test('returns null on non-200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 404, body: '{}');
      service.httpClientOverride = client;

      final profile = await service.getProfile(creds, 'unknown.bsky.social');
      expect(profile, isNull);
    });
  });

  group('getAuthorFeed (HTTP)', () {
    test('returns posts on 200', () async {
      final creds = makeBskyCreds();
      final feedJson = makeBskyFeedResponse();
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode(feedJson),
      );
      service.httpClientOverride = client;

      final result = await service.getAuthorFeed(creds, 'test.bsky.social');
      expect(result.posts, isNotEmpty);
    });

    test('throws BlueskyApiException on non-200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 500, body: '{}');
      service.httpClientOverride = client;

      expect(
        () => service.getAuthorFeed(creds, 'test.bsky.social'),
        throwsA(isA<BlueskyApiException>()),
      );
    });
  });

  group('follow (HTTP)', () {
    test('returns uri string on 200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({
          'uri': 'at://did:plc:test/app.bsky.graph.follow/followkey',
        }),
      );
      service.httpClientOverride = client;

      final uri = await service.follow(creds, 'did:plc:target');
      expect(uri, 'at://did:plc:test/app.bsky.graph.follow/followkey');
    });

    test('returns null on non-200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 400, body: '{}');
      service.httpClientOverride = client;

      final uri = await service.follow(creds, 'did:plc:target');
      expect(uri, isNull);
    });
  });

  group('unfollow (HTTP)', () {
    test('returns true on 200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 200, body: '{}');
      service.httpClientOverride = client;

      final result = await service.unfollow(
        creds,
        'at://did:plc:test/app.bsky.graph.follow/followkey',
      );
      expect(result, isTrue);
    });

    test('returns false on non-200', () async {
      final creds = makeBskyCreds();
      final client = createMockClient(statusCode: 500, body: '{}');
      service.httpClientOverride = client;

      final result = await service.unfollow(
        creds,
        'at://did:plc:test/app.bsky.graph.follow/followkey',
      );
      expect(result, isFalse);
    });
  });

  group('BlueskyApiException', () {
    test('toString includes message', () {
      final e = BlueskyApiException('test error');
      expect(e.toString(), contains('test error'));
      expect(e.message, 'test error');
    });
  });

  group('BlueskyAuthException', () {
    test('toString includes message', () {
      final e = BlueskyAuthException('auth failed');
      expect(e.toString(), contains('auth failed'));
      expect(e.message, 'auth failed');
    });
  });
}
