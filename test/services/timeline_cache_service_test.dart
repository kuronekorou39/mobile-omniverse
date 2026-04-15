import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/services/timeline_cache_service.dart';

import '../helpers/test_data.dart';

void main() {
  late TimelineCacheService service;
  late Directory tempDir;
  late File testFile;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    service = TimelineCacheService.instance;
    tempDir = Directory.systemTemp.createTempSync('timeline_cache_test_');
    testFile = File('${tempDir.path}/timeline_cache.json');
    service.cacheFileOverride = testFile;
  });

  tearDown(() {
    service.cacheFileOverride = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('TimelineCacheService', () {
    test('loadCachedTimeline returns empty list when no cache', () async {
      final posts = await service.loadCachedTimeline();
      expect(posts, isEmpty);
    });

    test('saveTimeline then loadCachedTimeline round-trip', () async {
      final posts = [
        makePost(id: 'x_c1', body: 'Cached 1'),
        makePost(id: 'x_c2', body: 'Cached 2'),
        makeBlueskyPost(id: 'bsky_c3'),
      ];

      await service.saveTimeline(posts);
      final loaded = await service.loadCachedTimeline();

      expect(loaded, hasLength(3));
      expect(loaded[0].id, 'x_c1');
      expect(loaded[0].body, 'Cached 1');
      expect(loaded[1].id, 'x_c2');
      expect(loaded[2].id, 'bsky_c3');
    });

    test('150 post limit truncates excess posts', () async {
      final posts = List.generate(
        200,
        (i) => makePost(id: 'x_$i', body: 'Post $i'),
      );

      await service.saveTimeline(posts);
      final loaded = await service.loadCachedTimeline();

      expect(loaded, hasLength(150));
      // First 150 should be preserved
      expect(loaded[0].id, 'x_0');
      expect(loaded[149].id, 'x_149');
    });

    test('clearCache removes data', () async {
      final posts = [makePost(id: 'x_del1')];
      await service.saveTimeline(posts);

      // Verify it was saved
      var loaded = await service.loadCachedTimeline();
      expect(loaded, hasLength(1));

      await service.clearCache();

      loaded = await service.loadCachedTimeline();
      expect(loaded, isEmpty);
    });

    test('corrupted JSON returns empty list gracefully', () async {
      // ファイルに不正なJSONを直接書き込み
      await testFile.writeAsString('not valid json {{{');

      final loaded = await service.loadCachedTimeline();
      expect(loaded, isEmpty);
    });

    test('corrupted individual post in list is skipped gracefully', () async {
      // JSONリスト内に不正なアイテムを含むデータ
      final validPost = makePost(id: 'x_valid', body: 'Valid').toJson();
      final invalidPost = {'id': null}; // Missing required 'id' as String
      final data = json.encode([validPost, invalidPost]);

      await testFile.writeAsString(data);

      final loaded = await service.loadCachedTimeline();
      // Only the valid post should be loaded; the invalid one is skipped
      expect(loaded, hasLength(1));
      expect(loaded[0].id, 'x_valid');
    });

    test('saving empty list clears effectively', () async {
      final posts = [makePost(id: 'x_old')];
      await service.saveTimeline(posts);

      await service.saveTimeline([]);

      final loaded = await service.loadCachedTimeline();
      expect(loaded, isEmpty);
    });

    test('post metadata survives round-trip', () async {
      final post = makePost(
        id: 'x_meta',
        body: 'With metadata',
        likeCount: 42,
        repostCount: 7,
        likedByAccountIds: {'test_account'},
        imageUrls: ['https://img.com/1.jpg'],
        permalink: 'https://x.com/test/status/meta',
      );

      await service.saveTimeline([post]);
      final loaded = await service.loadCachedTimeline();

      expect(loaded, hasLength(1));
      expect(loaded[0].likeCount, 42);
      expect(loaded[0].repostCount, 7);
      expect(loaded[0].isLiked, true);
      expect(loaded[0].imageUrls, ['https://img.com/1.jpg']);
      expect(loaded[0].permalink, 'https://x.com/test/status/meta');
    });

  });
}
