import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/post.dart';
import '../helpers/test_data.dart';

void main() {
  group('Post EngagementState', () {
    test('likeState returns none when no accounts liked', () {
      final post = makePost(
        fetchedByAccountIds: {'acc1', 'acc2'},
      );
      expect(post.likeState(), EngagementState.none);
    });

    test('likeState returns all when all fetching accounts liked', () {
      final post = makePost(
        fetchedByAccountIds: {'acc1', 'acc2'},
        likedByAccountIds: {'acc1', 'acc2'},
      );
      expect(post.likeState(), EngagementState.all);
    });

    test('likeState returns partial when some fetching accounts liked', () {
      final post = makePost(
        fetchedByAccountIds: {'acc1', 'acc2'},
        likedByAccountIds: {'acc1'},
      );
      expect(post.likeState(), EngagementState.partial);
    });

    test('repostState works same as likeState', () {
      final post = makePost(
        fetchedByAccountIds: {'acc1'},
        repostedByAccountIds: {'acc1'},
      );
      expect(post.repostState(), EngagementState.all);
    });

    test('isLikedBy returns correct result', () {
      final post = makePost(likedByAccountIds: {'acc1', 'acc2'});
      expect(post.isLikedBy('acc1'), true);
      expect(post.isLikedBy('acc3'), false);
    });

    test('isRepostedBy returns correct result', () {
      final post = makePost(repostedByAccountIds: {'acc1'});
      expect(post.isRepostedBy('acc1'), true);
      expect(post.isRepostedBy('acc2'), false);
    });

    test('isLiked getter returns true when any account liked', () {
      final post = makePost(likedByAccountIds: {'acc1'});
      expect(post.isLiked, true);
    });

    test('isLiked getter returns false when empty', () {
      final post = makePost();
      expect(post.isLiked, false);
    });

    test('bskyLikeUriFor returns correct URI', () {
      final post = makePost(bskyLikeUris: {'acc1': 'at://uri1'});
      expect(post.bskyLikeUriFor('acc1'), 'at://uri1');
      expect(post.bskyLikeUriFor('acc2'), isNull);
    });
  });

  group('Post cache compatibility', () {
    test('fromCache with old isLiked format', () {
      final json = {
        'id': 'x_123',
        'source': 'x',
        'username': 'Test',
        'handle': '@test',
        'body': 'hello',
        'timestamp': '2024-01-15T12:00:00.000Z',
        'accountId': 'acc1',
        'isLiked': true,
        'isReposted': false,
      };
      final post = Post.fromCache(json);
      expect(post.likedByAccountIds, {'acc1'});
      expect(post.repostedByAccountIds, isEmpty);
    });

    test('fromCache with new format', () {
      final json = {
        'id': 'x_123',
        'source': 'x',
        'username': 'Test',
        'handle': '@test',
        'body': 'hello',
        'timestamp': '2024-01-15T12:00:00.000Z',
        'likedByAccountIds': ['acc1', 'acc2'],
        'repostedByAccountIds': ['acc1'],
      };
      final post = Post.fromCache(json);
      expect(post.likedByAccountIds, {'acc1', 'acc2'});
      expect(post.repostedByAccountIds, {'acc1'});
    });
  });
}
