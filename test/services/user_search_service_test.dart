import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/user_search_service.dart';

void main() {
  group('normalizeHandle', () {
    test('strips a leading @', () {
      expect(UserSearchService.normalizeHandle('@alice'), 'alice');
      expect(UserSearchService.normalizeHandle('@@alice'), 'alice');
    });

    test('trims surrounding spaces', () {
      expect(UserSearchService.normalizeHandle('  alice  '), 'alice');
    });

    test('plain handle is left alone', () {
      expect(UserSearchService.normalizeHandle('alice'), 'alice');
      expect(
        UserSearchService.normalizeHandle('alice.bsky.social'),
        'alice.bsky.social',
      );
    });

    test('pulls the handle out of an x.com URL', () {
      expect(UserSearchService.normalizeHandle('https://x.com/alice'), 'alice');
      expect(UserSearchService.normalizeHandle('x.com/alice'), 'alice');
      expect(
        UserSearchService.normalizeHandle('https://www.twitter.com/alice'),
        'alice',
      );
    });

    test('pulls the handle out of a post URL', () {
      expect(
        UserSearchService.normalizeHandle('https://x.com/alice/status/12345'),
        'alice',
      );
    });

    test('pulls the handle out of a bsky.app profile URL', () {
      expect(
        UserSearchService.normalizeHandle(
            'https://bsky.app/profile/alice.bsky.social'),
        'alice.bsky.social',
      );
    });

    test('drops query strings and fragments', () {
      expect(
        UserSearchService.normalizeHandle('https://x.com/alice?s=20'),
        'alice',
      );
    });

    test('empty input yields empty output', () {
      expect(UserSearchService.normalizeHandle(''), '');
      expect(UserSearchService.normalizeHandle('   '), '');
      expect(UserSearchService.normalizeHandle('@'), '');
    });
  });

  group('fullTextQuery', () {
    test('keeps an ordinary phrase intact, spaces and all', () {
      expect(UserSearchService.fullTextQuery('山田 太郎'), '山田 太郎');
      expect(UserSearchService.fullTextQuery('cat photos'), 'cat photos');
    });

    test('turns @handle into a bare handle', () {
      expect(UserSearchService.fullTextQuery('@alice'), 'alice');
    });

    test('turns a pasted URL into a bare handle', () {
      expect(
        UserSearchService.fullTextQuery(
            'https://bsky.app/profile/alice.bsky.social'),
        'alice.bsky.social',
      );
    });

    test('a phrase containing a dot is not mistaken for a URL', () {
      expect(UserSearchService.fullTextQuery('Node.js 好き'), 'Node.js 好き');
    });
  });

  group('looksLikeHandleInput', () {
    test('true for @handle and known profile URLs', () {
      expect(UserSearchService.looksLikeHandleInput('@alice'), isTrue);
      expect(
          UserSearchService.looksLikeHandleInput('https://x.com/alice'), isTrue);
      expect(UserSearchService.looksLikeHandleInput('bsky.app/profile/a'),
          isTrue);
    });

    test('false for ordinary words and unrelated URLs', () {
      expect(UserSearchService.looksLikeHandleInput('alice'), isFalse);
      expect(UserSearchService.looksLikeHandleInput('山田 太郎'), isFalse);
      expect(UserSearchService.looksLikeHandleInput('https://example.com/a'),
          isFalse);
    });
  });

  group('fromXProfileMap', () {
    Map<String, dynamic> profile() => {
          'rest_id': '111',
          'name': 'アリス',
          'screen_name': 'alice',
          'description': 'bio',
          'followers_count': 120,
          'friends_count': 34,
          'statuses_count': 5678,
          'profile_image_url_https': 'https://cdn.example/a_400x400.jpg',
          'protected': false,
        };

    test('maps every field', () {
      final user = UserSearchService.fromXProfileMap(profile())!;

      expect(user.restId, '111');
      expect(user.screenName, 'alice');
      expect(user.name, 'アリス');
      expect(user.description, 'bio');
      expect(user.followersCount, 120);
      expect(user.friendsCount, 34);
      expect(user.statusesCount, 5678);
      expect(user.avatarUrl, 'https://cdn.example/a_400x400.jpg');
      expect(user.isProtected, isFalse);
    });

    test('null profile yields null', () {
      expect(UserSearchService.fromXProfileMap(null), isNull);
    });

    test('missing rest_id or screen_name yields null', () {
      expect(
        UserSearchService.fromXProfileMap(profile()..remove('rest_id')),
        isNull,
      );
      expect(
        UserSearchService.fromXProfileMap(profile()..remove('screen_name')),
        isNull,
      );
      expect(
        UserSearchService.fromXProfileMap(profile()..['rest_id'] = ''),
        isNull,
      );
    });

    test('missing optional fields fall back to empty values', () {
      final user = UserSearchService.fromXProfileMap({
        'rest_id': '222',
        'screen_name': 'bob',
      })!;

      expect(user.name, '');
      expect(user.description, '');
      expect(user.followersCount, 0);
      expect(user.avatarUrl, '');
      expect(user.isProtected, isFalse);
    });

    test('protected accounts are flagged', () {
      final user =
          UserSearchService.fromXProfileMap(profile()..['protected'] = true)!;
      expect(user.isProtected, isTrue);
    });
  });
}
