import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/post.dart';
import 'package:mobile_omniverse/models/sns_service.dart';

import '../helpers/test_data.dart';

void main() {
  group('Post', () {
    group('toJson / fromCache 往復', () {
      test('基本フィールドの往復', () {
        final post = makePost(
          id: 'x_999',
          username: 'Alice',
          handle: '@alice',
          body: 'Test body',
          likeCount: 10,
          replyCount: 3,
          repostCount: 5,
          isLiked: true,
          isReposted: false,
          permalink: 'https://x.com/alice/status/999',
          accountId: 'acc_1',
        );

        final json = post.toJson();
        final restored = Post.fromCache(json);

        expect(restored.id, 'x_999');
        expect(restored.source, SnsService.x);
        expect(restored.username, 'Alice');
        expect(restored.handle, '@alice');
        expect(restored.body, 'Test body');
        expect(restored.likeCount, 10);
        expect(restored.replyCount, 3);
        expect(restored.repostCount, 5);
        expect(restored.isLiked, true);
        expect(restored.isReposted, false);
        expect(restored.permalink, 'https://x.com/alice/status/999');
        expect(restored.accountId, 'acc_1');
      });

      test('Bluesky ソースの往復', () {
        final post = makeBlueskyPost();
        final json = post.toJson();
        final restored = Post.fromCache(json);

        expect(restored.source, SnsService.bluesky);
        expect(restored.id, 'bsky_abc');
      });

      test('メディアの往復', () {
        final post = makePost(
          imageUrls: ['https://img1.jpg', 'https://img2.jpg'],
          videoUrl: 'https://video.mp4',
          videoThumbnailUrl: 'https://thumb.jpg',
        );

        final json = post.toJson();
        final restored = Post.fromCache(json);

        expect(restored.imageUrls, ['https://img1.jpg', 'https://img2.jpg']);
        expect(restored.videoUrl, 'https://video.mp4');
        expect(restored.videoThumbnailUrl, 'https://thumb.jpg');
      });

      test('RT情報の往復', () {
        final post = makePost(
          isRetweet: true,
          retweetedByUsername: 'Bob',
          retweetedByHandle: '@bob',
        );

        final json = post.toJson();
        final restored = Post.fromCache(json);

        expect(restored.isRetweet, true);
        expect(restored.retweetedByUsername, 'Bob');
        expect(restored.retweetedByHandle, '@bob');
      });

      test('Bluesky固有フィールド (uri, cid) の往復', () {
        final post = makeBlueskyPost(
          uri: 'at://did:plc:test/app.bsky.feed.post/xyz',
          cid: 'bafyreicid456',
        );

        final json = post.toJson();
        final restored = Post.fromCache(json);

        expect(restored.uri, 'at://did:plc:test/app.bsky.feed.post/xyz');
        expect(restored.cid, 'bafyreicid456');
      });

      test('timestamp の往復', () {
        final ts = DateTime.utc(2024, 6, 15, 10, 30, 0);
        final post = makePost(timestamp: ts);

        final json = post.toJson();
        final restored = Post.fromCache(json);

        expect(restored.timestamp, ts);
      });

      test('inReplyToId の往復', () {
        final post = makePost(inReplyToId: 'parent_123');

        final json = post.toJson();
        final restored = Post.fromCache(json);

        expect(restored.inReplyToId, 'parent_123');
      });
    });

    group('quotedPost のネスト', () {
      test('引用ポスト付き toJson/fromCache 往復', () {
        final quoted = makePost(
          id: 'x_quoted_1',
          body: 'Quoted body',
          username: 'QuotedUser',
        );
        final post = makePost(
          id: 'x_main_1',
          body: 'Main body',
          quotedPost: quoted,
        );

        final json = post.toJson();
        final restored = Post.fromCache(json);

        expect(restored.quotedPost, isNotNull);
        expect(restored.quotedPost!.id, 'x_quoted_1');
        expect(restored.quotedPost!.body, 'Quoted body');
        expect(restored.quotedPost!.username, 'QuotedUser');
      });

      test('引用なしの場合 quotedPost は null', () {
        final post = makePost();
        final json = post.toJson();
        final restored = Post.fromCache(json);

        expect(restored.quotedPost, isNull);
      });
    });

    group('copyWith', () {
      test('likeCount を変更', () {
        final post = makePost(likeCount: 5);
        final updated = post.copyWith(likeCount: 10);

        expect(updated.likeCount, 10);
        expect(updated.id, post.id);
        expect(updated.body, post.body);
      });

      test('isLiked を変更', () {
        final post = makePost(isLiked: false);
        final updated = post.copyWith(isLiked: true);

        expect(updated.isLiked, true);
      });

      test('isReposted を変更', () {
        final post = makePost(isReposted: false);
        final updated = post.copyWith(isReposted: true);

        expect(updated.isReposted, true);
      });

      test('RT情報を設定', () {
        final post = makePost();
        final updated = post.copyWith(
          isRetweet: true,
          retweetedByUsername: 'Carol',
          retweetedByHandle: '@carol',
        );

        expect(updated.isRetweet, true);
        expect(updated.retweetedByUsername, 'Carol');
        expect(updated.retweetedByHandle, '@carol');
      });

      test('quotedPost を設定', () {
        final post = makePost();
        final quoted = makePost(id: 'quoted_1');
        final updated = post.copyWith(quotedPost: quoted);

        expect(updated.quotedPost, isNotNull);
        expect(updated.quotedPost!.id, 'quoted_1');
      });

      test('変更なしで同値', () {
        final post = makePost(likeCount: 5, isLiked: true);
        final updated = post.copyWith();

        expect(updated.likeCount, 5);
        expect(updated.isLiked, true);
      });
    });

    group('fromJson', () {
      test('基本的な JSON からの生成', () {
        final post = Post.fromJson({
          'id': 'json_1',
          'username': 'JsonUser',
          'handle': '@jsonuser',
          'body': 'From JSON',
          'timestamp': '2024-01-15T12:00:00.000Z',
        }, SnsService.x);

        expect(post.id, 'json_1');
        expect(post.username, 'JsonUser');
        expect(post.body, 'From JSON');
        expect(post.source, SnsService.x);
      });

      test('欠落フィールドにデフォルト値', () {
        final post = Post.fromJson({}, SnsService.bluesky);

        expect(post.username, '');
        expect(post.handle, '');
        expect(post.body, '');
        expect(post.source, SnsService.bluesky);
      });

      test('accountId 付き', () {
        final post = Post.fromJson(
          {'id': 'test'},
          SnsService.x,
          accountId: 'acc_123',
        );

        expect(post.accountId, 'acc_123');
      });
    });

    group('fromCache', () {
      test('不明なソースのフォールバック', () {
        final post = Post.fromCache({
          'id': 'test_1',
          'source': 'unknown_service',
          'username': 'Test',
          'handle': '@test',
          'body': 'test',
          'timestamp': '2024-01-15T12:00:00.000Z',
        });

        expect(post.source, SnsService.x); // デフォルトは x
      });

      test('null フィールドのデフォルト値', () {
        final post = Post.fromCache({
          'id': 'test_1',
          'source': 'x',
        });

        expect(post.username, '');
        expect(post.likeCount, 0);
        expect(post.isLiked, false);
        expect(post.imageUrls, isEmpty);
        expect(post.isRetweet, false);
      });
    });

    group('equality', () {
      test('同じ ID なら等価', () {
        final a = makePost(id: 'same_id', body: 'body A');
        final b = makePost(id: 'same_id', body: 'body B');

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('異なる ID なら非等価', () {
        final a = makePost(id: 'id_a');
        final b = makePost(id: 'id_b');

        expect(a, isNot(equals(b)));
      });
    });
  });
}
