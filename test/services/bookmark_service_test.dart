import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/services/bookmark_service.dart';

import '../helpers/test_data.dart';

void main() {
  // BookmarkService is a singleton, so we need a fresh instance for each test.
  // Since we cannot replace the singleton, we reinitialize its state via init().
  late BookmarkService service;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    service = BookmarkService.instance;
    service.resetForTest();
  });

  group('BookmarkService', () {
    test('init with empty prefs loads no bookmarks', () async {
      await service.init();

      expect(service.bookmarks, isEmpty);
    });

    test('toggle adds a bookmark', () async {
      await service.init();
      final post = makePost(id: 'x_1', body: 'First post');

      final isNowBookmarked = await service.toggle(post);

      expect(isNowBookmarked, true);
      expect(service.isBookmarked('x_1'), true);
      expect(service.bookmarks, hasLength(1));
      expect(service.bookmarks[0].id, 'x_1');
    });

    test('toggle removes a bookmark', () async {
      await service.init();
      final post = makePost(id: 'x_2', body: 'Second post');

      // Add
      await service.toggle(post);
      expect(service.isBookmarked('x_2'), true);

      // Remove
      final isNowBookmarked = await service.toggle(post);

      expect(isNowBookmarked, false);
      expect(service.isBookmarked('x_2'), false);
      expect(service.bookmarks, isEmpty);
    });

    test('isBookmarked returns correct state', () async {
      await service.init();
      final post1 = makePost(id: 'x_a');
      final post2 = makePost(id: 'x_b');

      await service.toggle(post1);

      expect(service.isBookmarked('x_a'), true);
      expect(service.isBookmarked('x_b'), false);
    });

    test('bookmarks list is unmodifiable', () async {
      await service.init();
      final post = makePost(id: 'x_unmod');
      await service.toggle(post);

      final list = service.bookmarks;
      expect(() => list.add(makePost(id: 'x_illegal')), throwsUnsupportedError);
    });

    test('multiple bookmarks maintain order (newest first)', () async {
      await service.init();
      final post1 = makePost(id: 'x_first', body: 'First');
      final post2 = makePost(id: 'x_second', body: 'Second');
      final post3 = makePost(id: 'x_third', body: 'Third');

      await service.toggle(post1);
      await service.toggle(post2);
      await service.toggle(post3);

      expect(service.bookmarks, hasLength(3));
      // Newest inserted at index 0
      expect(service.bookmarks[0].id, 'x_third');
      expect(service.bookmarks[1].id, 'x_second');
      expect(service.bookmarks[2].id, 'x_first');
    });

    test('bookmarks persist via SharedPreferences round-trip', () async {
      await service.init();
      final post = makePost(id: 'x_persist', body: 'Persistent post');
      await service.toggle(post);

      // Re-init from prefs (simulates app restart)
      await service.init();

      expect(service.isBookmarked('x_persist'), true);
      expect(service.bookmarks.any((p) => p.id == 'x_persist'), true);
    });

    test('toggle on already-bookmarked post and re-add works', () async {
      await service.init();
      final post = makePost(id: 'x_readd');

      await service.toggle(post); // add
      await service.toggle(post); // remove
      await service.toggle(post); // add again

      expect(service.isBookmarked('x_readd'), true);
      expect(service.bookmarks, hasLength(1));
    });

    test('bookmarking bluesky post works', () async {
      await service.init();
      final post = makeBlueskyPost(id: 'bsky_bm1');

      await service.toggle(post);

      expect(service.isBookmarked('bsky_bm1'), true);
      expect(service.bookmarks[0].id, 'bsky_bm1');
    });

    test('removing middle bookmark preserves order of others', () async {
      await service.init();
      final post1 = makePost(id: 'x_p1');
      final post2 = makePost(id: 'x_p2');
      final post3 = makePost(id: 'x_p3');

      await service.toggle(post1);
      await service.toggle(post2);
      await service.toggle(post3);

      // Remove the middle one
      await service.toggle(post2);

      expect(service.bookmarks, hasLength(2));
      expect(service.bookmarks[0].id, 'x_p3');
      expect(service.bookmarks[1].id, 'x_p1');
    });
  });
}
