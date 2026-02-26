import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/x_api_service.dart';
import 'package:mobile_omniverse/services/x_query_id_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_http_client.dart';
import '../helpers/test_data.dart';

void main() {
  final service = XApiService.instance;

  setUp(() {
    registerHttpFallbacks();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    service.httpClientOverride = null;
  });

  group('parseTweet', () {
    test('basic tweet parses correctly', () {
      final result = makeXTweetResult(
        tweetId: '111',
        screenName: 'alice',
        name: 'Alice',
        fullText: 'Hello world',
        favoriteCount: 42,
        retweetCount: 7,
        replyCount: 3,
        favorited: true,
        retweeted: false,
      );

      final post = service.parseTweet(result, 'acc1');

      expect(post, isNotNull);
      expect(post!.id, 'x_111');
      expect(post.source, SnsService.x);
      expect(post.username, 'Alice');
      expect(post.handle, '@alice');
      expect(post.body, 'Hello world');
      expect(post.likeCount, 42);
      expect(post.repostCount, 7);
      expect(post.replyCount, 3);
      expect(post.isLiked, true);
      expect(post.isReposted, false);
      expect(post.accountId, 'acc1');
      expect(post.permalink, 'https://x.com/alice/status/111');
    });

    test('RT detection via retweeted_status_result', () {
      final original = makeXTweetResult(
        tweetId: '200',
        screenName: 'original_author',
        name: 'Original Author',
        fullText: 'Original tweet',
      );

      final rt = makeXTweetResult(
        tweetId: '300',
        screenName: 'retweeter',
        name: 'Retweeter',
        fullText: 'RT @original_author: Original tweet',
        retweetedStatusResult: {'result': original},
      );

      final post = service.parseTweet(rt, null);

      expect(post, isNotNull);
      expect(post!.isRetweet, true);
      expect(post.retweetedByUsername, 'Retweeter');
      expect(post.retweetedByHandle, '@retweeter');
      // The post content should be from the original tweet
      expect(post.id, 'x_200');
      expect(post.username, 'Original Author');
      expect(post.body, 'Original tweet');
    });

    test('quote tweet via quoted_status_result', () {
      final quoted = makeXTweetResult(
        tweetId: '400',
        screenName: 'quoted_user',
        name: 'Quoted User',
        fullText: 'Quoted content',
      );

      final parent = makeXTweetResult(
        tweetId: '500',
        screenName: 'quoter',
        name: 'Quoter',
        fullText: 'Check this out',
        quotedStatusResult: {'result': quoted},
      );

      final post = service.parseTweet(parent, null);

      expect(post, isNotNull);
      expect(post!.id, 'x_500');
      expect(post.quotedPost, isNotNull);
      expect(post.quotedPost!.id, 'x_400');
      expect(post.quotedPost!.username, 'Quoted User');
      expect(post.quotedPost!.body, 'Quoted content');
    });

    test('photo media extraction', () {
      final result = makeXTweetResult(
        tweetId: '600',
        screenName: 'photographer',
        name: 'Photographer',
        fullText: 'Nice pic',
        media: [
          {
            'type': 'photo',
            'media_url_https': 'https://pbs.twimg.com/media/photo1.jpg',
            'url': 'https://t.co/abc',
          },
          {
            'type': 'photo',
            'media_url_https': 'https://pbs.twimg.com/media/photo2.jpg',
            'url': 'https://t.co/def',
          },
        ],
      );

      final post = service.parseTweet(result, null);

      expect(post, isNotNull);
      expect(post!.imageUrls, hasLength(2));
      expect(post.imageUrls[0], 'https://pbs.twimg.com/media/photo1.jpg');
      expect(post.imageUrls[1], 'https://pbs.twimg.com/media/photo2.jpg');
      expect(post.videoUrl, isNull);
    });

    test('video media extraction picks highest bitrate', () {
      final result = makeXTweetResult(
        tweetId: '700',
        screenName: 'videographer',
        name: 'Videographer',
        fullText: 'Cool video',
        media: [
          {
            'type': 'video',
            'media_url_https': 'https://pbs.twimg.com/ext_tw_video_thumb/thumb.jpg',
            'url': 'https://t.co/vid',
            'video_info': {
              'variants': [
                {
                  'content_type': 'application/x-mpegURL',
                  'url': 'https://video.twimg.com/playlist.m3u8',
                },
                {
                  'content_type': 'video/mp4',
                  'bitrate': 832000,
                  'url': 'https://video.twimg.com/832k.mp4',
                },
                {
                  'content_type': 'video/mp4',
                  'bitrate': 2176000,
                  'url': 'https://video.twimg.com/2176k.mp4',
                },
                {
                  'content_type': 'video/mp4',
                  'bitrate': 256000,
                  'url': 'https://video.twimg.com/256k.mp4',
                },
              ],
            },
          },
        ],
      );

      final post = service.parseTweet(result, null);

      expect(post, isNotNull);
      expect(post!.videoUrl, 'https://video.twimg.com/2176k.mp4');
      expect(post.videoThumbnailUrl,
          'https://pbs.twimg.com/ext_tw_video_thumb/thumb.jpg');
    });

    test('animated_gif media extraction', () {
      final result = makeXTweetResult(
        tweetId: '750',
        screenName: 'gifmaker',
        name: 'GIF Maker',
        fullText: 'Funny gif',
        media: [
          {
            'type': 'animated_gif',
            'media_url_https': 'https://pbs.twimg.com/tweet_video_thumb/gif.jpg',
            'url': 'https://t.co/gif',
            'video_info': {
              'variants': [
                {
                  'content_type': 'video/mp4',
                  'bitrate': 0,
                  'url': 'https://video.twimg.com/gif.mp4',
                },
              ],
            },
          },
        ],
      );

      final post = service.parseTweet(result, null);

      expect(post, isNotNull);
      expect(post!.videoUrl, 'https://video.twimg.com/gif.mp4');
      expect(post.videoThumbnailUrl,
          'https://pbs.twimg.com/tweet_video_thumb/gif.jpg');
    });

    test('t.co URL expansion replaces short URLs in text', () {
      final result = makeXTweetResult(
        tweetId: '800',
        screenName: 'linker',
        name: 'Linker',
        fullText: 'Check this https://t.co/abc123',
        urls: [
          {
            'url': 'https://t.co/abc123',
            'expanded_url': 'https://example.com/full-article',
          },
        ],
      );

      final post = service.parseTweet(result, null);

      expect(post, isNotNull);
      expect(post!.body, contains('https://example.com/full-article'));
      expect(post.body, isNot(contains('https://t.co/abc123')));
    });

    test('TweetWithVisibilityResults typename unwraps tweet data', () {
      final innerTweet = makeXTweetResult(
        tweetId: '900',
        screenName: 'visible',
        name: 'Visible User',
        fullText: 'Visibility limited tweet',
      );

      final wrapped = <String, dynamic>{
        '__typename': 'TweetWithVisibilityResults',
        'tweet': innerTweet,
      };

      final post = service.parseTweet(wrapped, null);

      expect(post, isNotNull);
      expect(post!.id, 'x_900');
      expect(post.body, 'Visibility limited tweet');
    });

    test('null legacy returns null', () {
      final result = <String, dynamic>{
        '__typename': 'Tweet',
        'legacy': null,
        'core': {},
      };

      final post = service.parseTweet(result, null);
      expect(post, isNull);
    });

    test('missing core/user_results gives empty username', () {
      final result = <String, dynamic>{
        '__typename': 'Tweet',
        'legacy': <String, dynamic>{
          'id_str': '999',
          'full_text': 'No user info',
          'created_at': 'Mon Jan 15 12:00:00 +0000 2024',
          'favorite_count': 0,
          'retweet_count': 0,
          'reply_count': 0,
          'favorited': false,
          'retweeted': false,
          'entities': <String, dynamic>{},
        },
      };

      final post = service.parseTweet(result, null);

      expect(post, isNotNull);
      expect(post!.username, '');
      expect(post.handle, '@');
    });

    test('inReplyToId is extracted', () {
      final result = makeXTweetResult(
        tweetId: '1000',
        screenName: 'replier',
        name: 'Replier',
        fullText: '@someone reply text',
      );
      // Manually inject in_reply_to_status_id_str
      (result['legacy'] as Map<String, dynamic>)['in_reply_to_status_id_str'] =
          '999';

      final post = service.parseTweet(result, null);

      expect(post, isNotNull);
      expect(post!.inReplyToId, '999');
    });

    test('media URLs removed from text', () {
      final result = makeXTweetResult(
        tweetId: '1100',
        screenName: 'mediaposter',
        name: 'Media Poster',
        fullText: 'Look at this https://t.co/media1',
        media: [
          {
            'type': 'photo',
            'media_url_https': 'https://pbs.twimg.com/media/photo.jpg',
            'url': 'https://t.co/media1',
          },
        ],
      );

      final post = service.parseTweet(result, null);

      expect(post, isNotNull);
      expect(post!.body, isNot(contains('https://t.co/media1')));
      expect(post.body.trim(), 'Look at this');
    });

    test('quote tweet URL removed from text', () {
      final quoted = makeXTweetResult(
        tweetId: '1200',
        screenName: 'quoteduser',
        name: 'Quoted',
        fullText: 'Original text',
      );

      final result = makeXTweetResult(
        tweetId: '1300',
        screenName: 'quoter',
        name: 'Quoter',
        fullText: 'My thoughts https://x.com/quoteduser/status/1200',
        quotedStatusResult: {'result': quoted},
      );

      final post = service.parseTweet(result, null);

      expect(post, isNotNull);
      expect(post!.body, isNot(contains('https://x.com/quoteduser/status/1200')));
    });
  });

  group('parseTimeline', () {
    test('parses tweets from standard timeline response', () {
      final tweet1 = makeXTweetResult(tweetId: '1', fullText: 'First');
      final tweet2 = makeXTweetResult(tweetId: '2', fullText: 'Second');

      final body = makeXTimelineResponse([tweet1, tweet2]);
      final posts = service.parseTimeline(body, 'acc1');

      expect(posts, hasLength(2));
      expect(posts[0].id, 'x_1');
      expect(posts[1].id, 'x_2');
    });

    test('promoted entries with promoted- prefix are skipped', () {
      final body = {
        'data': {
          'home': {
            'home_timeline_urt': {
              'instructions': [
                {
                  'type': 'TimelineAddEntries',
                  'entries': [
                    {
                      'entryId': 'promoted-tweet-123',
                      'content': {
                        'entryType': 'TimelineTimelineItem',
                        'itemContent': {
                          'tweet_results': {
                            'result': makeXTweetResult(
                              tweetId: 'promo1',
                              fullText: 'Buy our product',
                            ),
                          },
                        },
                      },
                    },
                    {
                      'entryId': 'tweet-0',
                      'content': {
                        'entryType': 'TimelineTimelineItem',
                        'itemContent': {
                          'tweet_results': {
                            'result': makeXTweetResult(
                              tweetId: 'real1',
                              fullText: 'Real tweet',
                            ),
                          },
                        },
                      },
                    },
                  ],
                },
              ],
            },
          },
        },
      };

      final posts = service.parseTimeline(body, null);

      expect(posts, hasLength(1));
      expect(posts[0].body, 'Real tweet');
    });

    test('promotedTweet- prefix entries are skipped', () {
      final body = {
        'data': {
          'home': {
            'home_timeline_urt': {
              'instructions': [
                {
                  'type': 'TimelineAddEntries',
                  'entries': [
                    {
                      'entryId': 'promotedTweet-abc',
                      'content': {
                        'entryType': 'TimelineTimelineItem',
                        'itemContent': {
                          'tweet_results': {
                            'result': makeXTweetResult(tweetId: 'ad'),
                          },
                        },
                      },
                    },
                  ],
                },
              ],
            },
          },
        },
      };

      final posts = service.parseTimeline(body, null);
      expect(posts, isEmpty);
    });

    test('entries with promotedMetadata in itemContent are skipped', () {
      final body = {
        'data': {
          'home': {
            'home_timeline_urt': {
              'instructions': [
                {
                  'type': 'TimelineAddEntries',
                  'entries': [
                    {
                      'entryId': 'tweet-0',
                      'content': {
                        'entryType': 'TimelineTimelineItem',
                        'itemContent': {
                          'promotedMetadata': {'advertiser': 'SomeCompany'},
                          'tweet_results': {
                            'result': makeXTweetResult(tweetId: 'sneaky_ad'),
                          },
                        },
                      },
                    },
                  ],
                },
              ],
            },
          },
        },
      };

      final posts = service.parseTimeline(body, null);
      expect(posts, isEmpty);
    });

    test('TimelineAddEntries type filter skips other instruction types', () {
      final body = {
        'data': {
          'home': {
            'home_timeline_urt': {
              'instructions': [
                {
                  'type': 'TimelineClearCache',
                },
                {
                  'type': 'TimelineAddEntries',
                  'entries': [
                    {
                      'entryId': 'tweet-0',
                      'content': {
                        'entryType': 'TimelineTimelineItem',
                        'itemContent': {
                          'tweet_results': {
                            'result': makeXTweetResult(tweetId: 'real'),
                          },
                        },
                      },
                    },
                  ],
                },
              ],
            },
          },
        },
      };

      final posts = service.parseTimeline(body, null);
      expect(posts, hasLength(1));
    });

    test('empty instructions returns empty list', () {
      final body = {
        'data': {
          'home': {
            'home_timeline_urt': {
              'instructions': <dynamic>[],
            },
          },
        },
      };

      final posts = service.parseTimeline(body, null);
      expect(posts, isEmpty);
    });

    test('missing instructions path returns empty list', () {
      final body = <String, dynamic>{
        'data': {
          'something_else': {},
        },
      };

      final posts = service.parseTimeline(body, null);
      expect(posts, isEmpty);
    });

    test('home_latest path is also tried', () {
      final body = {
        'data': {
          'home_latest': {
            'home_latest_timeline_urt': {
              'instructions': [
                {
                  'type': 'TimelineAddEntries',
                  'entries': [
                    {
                      'entryId': 'tweet-0',
                      'content': {
                        'entryType': 'TimelineTimelineItem',
                        'itemContent': {
                          'tweet_results': {
                            'result': makeXTweetResult(
                              tweetId: 'latest1',
                              fullText: 'Latest path',
                            ),
                          },
                        },
                      },
                    },
                  ],
                },
              ],
            },
          },
        },
      };

      final posts = service.parseTimeline(body, null);
      expect(posts, hasLength(1));
      expect(posts[0].body, 'Latest path');
    });

    test('latest_timeline path is also tried', () {
      final body = {
        'data': {
          'home': {
            'latest_timeline': {
              'instructions': [
                {
                  'type': 'TimelineAddEntries',
                  'entries': [
                    {
                      'entryId': 'tweet-0',
                      'content': {
                        'entryType': 'TimelineTimelineItem',
                        'itemContent': {
                          'tweet_results': {
                            'result': makeXTweetResult(
                              tweetId: 'alt1',
                              fullText: 'Alt path',
                            ),
                          },
                        },
                      },
                    },
                  ],
                },
              ],
            },
          },
        },
      };

      final posts = service.parseTimeline(body, null);
      expect(posts, hasLength(1));
      expect(posts[0].body, 'Alt path');
    });

    test('non-TimelineTimelineItem entryType is skipped', () {
      final body = {
        'data': {
          'home': {
            'home_timeline_urt': {
              'instructions': [
                {
                  'type': 'TimelineAddEntries',
                  'entries': [
                    {
                      'entryId': 'cursor-top',
                      'content': {
                        'entryType': 'TimelineTimelineCursor',
                        'value': 'abc123',
                      },
                    },
                  ],
                },
              ],
            },
          },
        },
      };

      final posts = service.parseTimeline(body, null);
      expect(posts, isEmpty);
    });
  });

  group('parseTweetDetailResponse', () {
    test('parses tweet- entryId as TimelineTimelineItem', () {
      final body = {
        'data': {
          'threaded_conversation_with_injections_v2': {
            'instructions': [
              {
                'type': 'TimelineAddEntries',
                'entries': [
                  {
                    'entryId': 'tweet-123',
                    'content': {
                      'entryType': 'TimelineTimelineItem',
                      'itemContent': {
                        'tweet_results': {
                          'result': makeXTweetResult(
                            tweetId: '123',
                            fullText: 'Main tweet',
                          ),
                        },
                      },
                    },
                  },
                ],
              },
            ],
          },
        },
      };

      final posts = service.parseTweetDetailResponse(body, null);
      expect(posts, hasLength(1));
      expect(posts[0].id, 'x_123');
    });

    test('parses conversationthread- with TimelineTimelineModule (replies)', () {
      final body = {
        'data': {
          'threaded_conversation_with_injections_v2': {
            'instructions': [
              {
                'type': 'TimelineAddEntries',
                'entries': [
                  {
                    'entryId': 'conversationthread-456',
                    'content': {
                      'entryType': 'TimelineTimelineModule',
                      'items': [
                        {
                          'item': {
                            'itemContent': {
                              'tweet_results': {
                                'result': makeXTweetResult(
                                  tweetId: '456',
                                  fullText: 'Reply 1',
                                ),
                              },
                            },
                          },
                        },
                        {
                          'item': {
                            'itemContent': {
                              'tweet_results': {
                                'result': makeXTweetResult(
                                  tweetId: '457',
                                  fullText: 'Reply 2',
                                ),
                              },
                            },
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            ],
          },
        },
      };

      final posts = service.parseTweetDetailResponse(body, null);
      expect(posts, hasLength(2));
      expect(posts[0].id, 'x_456');
      expect(posts[1].id, 'x_457');
    });

    test('non-matching entryId (cursor-, whoToFollow-) is skipped', () {
      final body = {
        'data': {
          'threaded_conversation_with_injections_v2': {
            'instructions': [
              {
                'type': 'TimelineAddEntries',
                'entries': [
                  {
                    'entryId': 'cursor-bottom',
                    'content': {
                      'entryType': 'TimelineTimelineCursor',
                      'value': 'xyz',
                    },
                  },
                  {
                    'entryId': 'whoToFollow-123',
                    'content': {
                      'entryType': 'TimelineTimelineModule',
                      'items': [],
                    },
                  },
                ],
              },
            ],
          },
        },
      };

      final posts = service.parseTweetDetailResponse(body, null);
      expect(posts, isEmpty);
    });

    test('empty instructions returns empty list', () {
      final body = {
        'data': {
          'threaded_conversation_with_injections_v2': {
            'instructions': <dynamic>[],
          },
        },
      };

      final posts = service.parseTweetDetailResponse(body, null);
      expect(posts, isEmpty);
    });

    test('missing path returns empty list', () {
      final body = <String, dynamic>{'data': {}};
      final posts = service.parseTweetDetailResponse(body, null);
      expect(posts, isEmpty);
    });
  });

  group('parseTwitterDate', () {
    test('valid date "Wed Oct 10 20:19:24 +0000 2018"', () {
      final dt = service.parseTwitterDate('Wed Oct 10 20:19:24 +0000 2018');

      expect(dt.year, 2018);
      expect(dt.month, 10);
      expect(dt.day, 10);
      expect(dt.hour, 20);
      expect(dt.minute, 19);
      expect(dt.second, 24);
    });

    test('invalid/short string returns DateTime close to now', () {
      final before = DateTime.now();
      final dt = service.parseTwitterDate('bad');
      final after = DateTime.now();

      expect(dt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(dt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('empty string returns DateTime close to now', () {
      final before = DateTime.now();
      final dt = service.parseTwitterDate('');
      final after = DateTime.now();

      expect(dt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(dt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('all months parse correctly', () {
      final months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4,
        'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8,
        'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };

      for (final entry in months.entries) {
        final dateStr = 'Mon ${entry.key} 15 10:00:00 +0000 2024';
        final dt = service.parseTwitterDate(dateStr);
        expect(dt.month, entry.value,
            reason: '${entry.key} should parse to month ${entry.value}');
      }
    });
  });

  group('dig', () {
    test('nested map traversal returns value', () {
      final map = {
        'a': {
          'b': {
            'c': 'found',
          },
        },
      };

      final result = service.dig(map, ['a', 'b', 'c']);
      expect(result, 'found');
    });

    test('missing key returns null', () {
      final map = {
        'a': {'b': 'value'},
      };

      final result = service.dig(map, ['a', 'x', 'c']);
      expect(result, isNull);
    });

    test('non-map intermediate returns null', () {
      final map = {
        'a': 'not a map',
      };

      final result = service.dig(map, ['a', 'b']);
      expect(result, isNull);
    });

    test('empty keys returns the map itself', () {
      final map = {'key': 'value'};

      final result = service.dig(map, []);
      expect(result, map);
    });

    test('single key traversal', () {
      final map = {'key': 42};

      final result = service.dig(map, ['key']);
      expect(result, 42);
    });

    test('deeply nested list value', () {
      final map = {
        'data': {
          'items': [1, 2, 3],
        },
      };

      final result = service.dig(map, ['data', 'items']);
      expect(result, [1, 2, 3]);
    });
  });

  // ===== HTTP-level tests =====

  group('getTimeline (HTTP)', () {
    test('returns posts on 200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final tweetData = makeXTweetResult(tweetId: 'ht1', fullText: 'Timeline tweet');
      final timelineJson = makeXTimelineResponse([tweetData]);

      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode(timelineJson),
      );
      service.httpClientOverride = client;

      final posts = await service.getTimeline(creds);
      expect(posts, isNotEmpty);
      expect(posts.first.id, 'x_ht1');
      expect(posts.first.body, 'Timeline tweet');
    });

    test('throws XAuthException on 401', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 401, body: '{}');
      service.httpClientOverride = client;

      expect(
        () => service.getTimeline(creds),
        throwsA(isA<XAuthException>()),
      );
    });

    test('throws XAuthException on 403', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 403, body: '{}');
      service.httpClientOverride = client;

      expect(
        () => service.getTimeline(creds),
        throwsA(isA<XAuthException>()),
      );
    });

    test('throws XApiException on 500', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 500, body: '{}');
      service.httpClientOverride = client;

      expect(
        () => service.getTimeline(creds),
        throwsA(isA<XApiException>()),
      );
    });

    test('passes accountId through to parsed posts', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final tweetData = makeXTweetResult(tweetId: 'acc_test');
      final timelineJson = makeXTimelineResponse([tweetData]);

      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode(timelineJson),
      );
      service.httpClientOverride = client;

      final posts = await service.getTimeline(creds, accountId: 'my_acc');
      expect(posts.first.accountId, 'my_acc');
    });
  });

  group('getTweetDetail (HTTP)', () {
    test('returns posts on 200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final detailJson = {
        'data': {
          'threaded_conversation_with_injections_v2': {
            'instructions': [
              {
                'type': 'TimelineAddEntries',
                'entries': [
                  {
                    'entryId': 'tweet-999',
                    'content': {
                      'entryType': 'TimelineTimelineItem',
                      'itemContent': {
                        'tweet_results': {
                          'result': makeXTweetResult(
                            tweetId: '999',
                            fullText: 'Detail tweet',
                          ),
                        },
                      },
                    },
                  },
                ],
              },
            ],
          },
        },
      };

      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode(detailJson),
      );
      service.httpClientOverride = client;

      final posts = await service.getTweetDetail(creds, '999');
      expect(posts, isNotEmpty);
      expect(posts.first.id, 'x_999');
    });

    test('throws XAuthException on 401', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 401, body: '{}');
      service.httpClientOverride = client;

      expect(
        () => service.getTweetDetail(creds, '123'),
        throwsA(isA<XAuthException>()),
      );
    });

    test('throws XApiException on 404', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      // 404 triggers queryId retry via XQueryIdService.forceRefresh
      // Mock both the API client and the query id service client so no real HTTP calls happen
      final client = createMockClient(statusCode: 404, body: '{}');
      service.httpClientOverride = client;

      // Also set up XQueryIdService httpClientOverride to avoid real network calls
      final queryIdClient = createMockClient(statusCode: 500, body: '');
      XQueryIdService.instance.httpClientOverride = queryIdClient;

      try {
        await service.getTweetDetail(creds, '123');
        fail('Should have thrown');
      } on XApiException catch (e) {
        expect(e.statusCode, 404);
      } finally {
        XQueryIdService.instance.httpClientOverride = null;
      }
    });
  });

  group('likeTweet (HTTP)', () {
    test('returns true on 200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({'data': {'favorite_tweet': 'Done'}}),
      );
      service.httpClientOverride = client;

      final result = await service.likeTweet(creds, 'tweet_1');
      expect(result, isTrue);
    });

    test('returns false on non-200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 403, body: '{"errors":[]}');
      service.httpClientOverride = client;

      final result = await service.likeTweet(creds, 'tweet_1');
      expect(result, isFalse);
    });
  });

  group('likeTweetWithDetail (HTTP)', () {
    test('returns XApiResult with success on 200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({'data': {'favorite_tweet': 'Done'}}),
      );
      service.httpClientOverride = client;

      final result = await service.likeTweetWithDetail(creds, 'tweet_1');
      expect(result.success, isTrue);
      expect(result.statusCode, 200);
      expect(result.bodySnippet, isNotNull);
    });
  });

  group('unlikeTweet (HTTP)', () {
    test('returns true on 200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({'data': {'unfavorite_tweet': 'Done'}}),
      );
      service.httpClientOverride = client;

      final result = await service.unlikeTweet(creds, 'tweet_1');
      expect(result, isTrue);
    });

    test('returns false on non-200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 500, body: '{}');
      service.httpClientOverride = client;

      final result = await service.unlikeTweet(creds, 'tweet_1');
      expect(result, isFalse);
    });
  });

  group('unlikeTweetWithDetail (HTTP)', () {
    test('returns XApiResult with success on 200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(
        statusCode: 200,
        body: '{"data":{"unfavorite_tweet":"Done"}}',
      );
      service.httpClientOverride = client;

      final result = await service.unlikeTweetWithDetail(creds, 'tweet_1');
      expect(result.success, isTrue);
      expect(result.statusCode, 200);
    });
  });

  group('retweet (HTTP)', () {
    test('returns true on 200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({'data': {'create_retweet': {'retweet_results': {}}}}),
      );
      service.httpClientOverride = client;

      final result = await service.retweet(creds, 'tweet_1');
      expect(result, isTrue);
    });

    test('returns false on non-200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 403, body: '{}');
      service.httpClientOverride = client;

      final result = await service.retweet(creds, 'tweet_1');
      expect(result, isFalse);
    });
  });

  group('retweetWithDetail (HTTP)', () {
    test('returns XApiResult with correct data', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 200, body: '{"ok":true}');
      service.httpClientOverride = client;

      final result = await service.retweetWithDetail(creds, 'tweet_1');
      expect(result.success, isTrue);
      expect(result.statusCode, 200);
    });
  });

  group('unretweet (HTTP)', () {
    test('returns true on 200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({'data': {'unretweet': {'unretweet_results': {}}}}),
      );
      service.httpClientOverride = client;

      final result = await service.unretweet(creds, 'tweet_1');
      expect(result, isTrue);
    });

    test('returns false on non-200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 400, body: '{}');
      service.httpClientOverride = client;

      final result = await service.unretweet(creds, 'tweet_1');
      expect(result, isFalse);
    });
  });

  group('unretweetWithDetail (HTTP)', () {
    test('returns XApiResult with correct data', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 200, body: '{"ok":true}');
      service.httpClientOverride = client;

      final result = await service.unretweetWithDetail(creds, 'tweet_1');
      expect(result.success, isTrue);
      expect(result.statusCode, 200);
    });
  });

  group('createTweet (HTTP)', () {
    test('returns success on 200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(
        statusCode: 200,
        body: jsonEncode({'data': {'create_tweet': {'tweet_results': {}}}}),
      );
      service.httpClientOverride = client;

      final result = await service.createTweet(creds, 'Hello from test');
      expect(result.success, isTrue);
      expect(result.statusCode, 200);
    });

    test('returns failure on non-200', () async {
      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final client = createMockClient(statusCode: 403, body: '{"errors":[]}');
      service.httpClientOverride = client;

      final result = await service.createTweet(creds, 'Hello from test');
      expect(result.success, isFalse);
      expect(result.statusCode, 403);
    });
  });

  group('XApiException', () {
    test('toString includes message', () {
      final e = XApiException('test error', statusCode: 500);
      expect(e.toString(), contains('test error'));
      expect(e.statusCode, 500);
      expect(e.message, 'test error');
    });
  });

  group('XAuthException', () {
    test('toString includes message', () {
      final e = XAuthException('auth failed');
      expect(e.toString(), contains('auth failed'));
      expect(e.message, 'auth failed');
    });
  });

  group('XApiResult', () {
    test('holds success, statusCode and bodySnippet', () {
      const r = XApiResult(success: true, statusCode: 200, bodySnippet: 'ok');
      expect(r.success, isTrue);
      expect(r.statusCode, 200);
      expect(r.bodySnippet, 'ok');
    });

    test('bodySnippet can be null', () {
      const r = XApiResult(success: false, statusCode: 500);
      expect(r.bodySnippet, isNull);
    });
  });
}
