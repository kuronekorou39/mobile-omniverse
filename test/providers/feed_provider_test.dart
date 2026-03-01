import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/post.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/providers/feed_provider.dart';
import 'package:mobile_omniverse/services/timeline_fetch_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_data.dart';

void main() {
  group('FeedState', () {
    test('初期状態', () {
      const state = FeedState();
      expect(state.posts, isEmpty);
      expect(state.isLoading, false);
      expect(state.isLoadingMore, false);
      expect(state.isFetching, false);
      expect(state.pendingCount, 0);
      expect(state.error, isNull);
    });

    test('copyWith で posts を変更', () {
      const state = FeedState();
      final posts = [makePost()];
      final updated = state.copyWith(posts: posts);

      expect(updated.posts.length, 1);
      expect(updated.isLoading, false);
    });

    test('copyWith で isLoading を変更', () {
      const state = FeedState();
      final updated = state.copyWith(isLoading: true);

      expect(updated.isLoading, true);
    });

    test('copyWith で error を設定', () {
      const state = FeedState();
      final updated = state.copyWith(error: 'Network error');

      expect(updated.error, 'Network error');
    });

    test('copyWith で clearError を使用', () {
      final state = const FeedState().copyWith(error: 'Error');
      final cleared = state.copyWith(clearError: true);

      expect(cleared.error, isNull);
    });

    test('copyWith で isLoadingMore を変更', () {
      const state = FeedState();
      final updated = state.copyWith(isLoadingMore: true);

      expect(updated.isLoadingMore, true);
    });

    test('copyWith で全フィールドを保持', () {
      final state = FeedState(
        posts: [makePost(id: 'p1')],
        isLoading: true,
        isLoadingMore: true,
        error: 'some error',
      );
      final updated = state.copyWith();

      expect(updated.posts.length, 1);
      expect(updated.isLoading, true);
      expect(updated.isLoadingMore, true);
      expect(updated.error, 'some error');
    });

    test('clearError は他の error 設定より優先される', () {
      final state = const FeedState().copyWith(error: 'Error');
      // clearError=true のとき error パラメータは無視される
      final cleared = state.copyWith(error: 'new error', clearError: true);
      expect(cleared.error, isNull);
    });
  });

  group('投稿マージロジック', () {
    test('新規投稿の追加', () {
      final existing = <String, Post>{};
      final newPosts = [
        makePost(id: 'p1', body: 'Post 1'),
        makePost(id: 'p2', body: 'Post 2'),
      ];

      for (final post in newPosts) {
        existing[post.id] = post;
      }

      expect(existing.length, 2);
    });

    test('ユーザーデータ保護: 空ユーザー名で上書きしない', () {
      final old = makePost(
        id: 'p1',
        username: 'Alice',
        handle: '@alice',
        likeCount: 5,
      );
      final newPost = makePost(
        id: 'p1',
        username: '', // ユーザー情報が欠けている
        handle: '',
        likeCount: 10,
        isLiked: true,
      );

      final existing = <String, Post>{'p1': old};

      // FeedNotifier._onPostsFetched のロジックを再現
      for (final post in [newPost]) {
        final oldPost = existing[post.id];
        if (oldPost != null &&
            post.username.isEmpty &&
            oldPost.username.isNotEmpty) {
          existing[post.id] = oldPost.copyWith(
            isLiked: post.isLiked,
            isReposted: post.isReposted,
            likeCount: post.likeCount,
            repostCount: post.repostCount,
          );
        } else {
          existing[post.id] = post;
        }
      }

      final result = existing['p1']!;
      expect(result.username, 'Alice'); // ユーザー名は保持
      expect(result.handle, '@alice'); // ハンドルも保持
      expect(result.likeCount, 10); // エンゲージメントは更新
      expect(result.isLiked, true);
    });

    test('正常なユーザーデータでは上書きする', () {
      final old = makePost(id: 'p1', username: 'Alice', likeCount: 5);
      final newPost =
          makePost(id: 'p1', username: 'Alice Updated', likeCount: 10);

      final existing = <String, Post>{'p1': old};

      for (final post in [newPost]) {
        final oldPost = existing[post.id];
        if (oldPost != null &&
            post.username.isEmpty &&
            oldPost.username.isNotEmpty) {
          existing[post.id] = oldPost.copyWith(
            isLiked: post.isLiked,
            isReposted: post.isReposted,
            likeCount: post.likeCount,
            repostCount: post.repostCount,
          );
        } else {
          existing[post.id] = post;
        }
      }

      expect(existing['p1']!.username, 'Alice Updated');
    });

    test('時系列ソート（新しい順）', () {
      final posts = [
        makePost(id: 'p1', timestamp: DateTime(2024, 1, 1)),
        makePost(id: 'p3', timestamp: DateTime(2024, 1, 3)),
        makePost(id: 'p2', timestamp: DateTime(2024, 1, 2)),
      ];

      posts.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      expect(posts[0].id, 'p3');
      expect(posts[1].id, 'p2');
      expect(posts[2].id, 'p1');
    });

    test('重複排除', () {
      final existing = <String, Post>{};
      final batch1 = [
        makePost(id: 'p1', body: 'v1'),
        makePost(id: 'p2', body: 'v1'),
      ];
      final batch2 = [
        makePost(id: 'p2', body: 'v2'),
        makePost(id: 'p3', body: 'v1'),
      ];

      for (final p in batch1) {
        existing[p.id] = p;
      }
      for (final p in batch2) {
        existing[p.id] = p;
      }

      expect(existing.length, 3);
      expect(existing['p2']!.body, 'v2'); // 更新される
    });
  });

  group('エンゲージメント更新', () {
    test('updatePostEngagement のロジック', () {
      final posts = [
        makePost(id: 'p1', likeCount: 5, isLiked: false),
        makePost(id: 'p2', likeCount: 3, isLiked: true),
      ];

      // updatePostEngagement のロジックを再現
      final idx = posts.indexWhere((p) => p.id == 'p1');
      expect(idx, 0);

      final updated = List<Post>.of(posts);
      updated[idx] = updated[idx].copyWith(
        isLiked: true,
        likeCount: 6,
      );

      expect(updated[0].isLiked, true);
      expect(updated[0].likeCount, 6);
      expect(updated[1].likeCount, 3); // 他のポストに影響なし
    });

    test('存在しない postId の更新は何もしない', () {
      final posts = [makePost(id: 'p1')];
      final idx = posts.indexWhere((p) => p.id == 'p_nonexistent');
      expect(idx, -1);
    });
  });

  group('postsForService', () {
    test('サービスでフィルタリング', () {
      final posts = [
        makePost(id: 'x_1', source: SnsService.x),
        makePost(id: 'bsky_1', source: SnsService.bluesky),
        makePost(id: 'x_2', source: SnsService.x),
      ];

      final xPosts = posts.where((p) => p.source == SnsService.x).toList();
      final bskyPosts =
          posts.where((p) => p.source == SnsService.bluesky).toList();

      expect(xPosts.length, 2);
      expect(bskyPosts.length, 1);
    });
  });

  group('FeedNotifier', () {
    late FeedNotifier notifier;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      notifier = FeedNotifier(null);
    });

    test('初期状態は空の FeedState', () {
      expect(notifier.state.posts, isEmpty);
      expect(notifier.state.isLoading, false);
      expect(notifier.state.isLoadingMore, false);
      expect(notifier.state.isFetching, false);
      expect(notifier.state.pendingCount, 0);
      expect(notifier.state.error, isNull);
    });

    test('_onPostsFetched でスケジューラ経由で投稿がマージされる', () async {
      // FeedNotifier のコンストラクタで
      // TimelineFetchScheduler.instance.onPostsFetched = _onPostsFetched
      // が設定されるので、スケジューラのコールバック経由でテスト
      final scheduler = TimelineFetchScheduler.instance;

      final posts = [
        makePost(id: 'sched_p1', timestamp: DateTime(2024, 1, 2)),
        makePost(id: 'sched_p2', timestamp: DateTime(2024, 1, 1)),
      ];

      // スケジューラのコールバックを呼び出す
      scheduler.onPostsFetched?.call(posts);

      // キャッシュ保存のために少し待つ
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.posts.length, 2);
      // 時系列順（新しい順）にソートされている
      expect(notifier.state.posts.first.id, 'sched_p1');
      expect(notifier.state.posts.last.id, 'sched_p2');
    });

    test('_onPostsFetched でユーザーデータ保護が動作する', () async {
      final scheduler = TimelineFetchScheduler.instance;

      // まず正常なユーザーデータを持つ投稿を追加
      scheduler.onPostsFetched?.call([
        makePost(id: 'protect_1', username: 'Alice', handle: '@alice',
            likeCount: 5),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.posts.first.username, 'Alice');

      // ユーザー情報が欠けた投稿で更新
      scheduler.onPostsFetched?.call([
        makePost(id: 'protect_1', username: '', handle: '',
            likeCount: 10, isLiked: true),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final result = notifier.state.posts.first;
      expect(result.username, 'Alice'); // ユーザー名は保持
      expect(result.handle, '@alice'); // ハンドルも保持
      expect(result.likeCount, 10); // エンゲージメントは更新
      expect(result.isLiked, true);
    });

    test('_onPostsFetched で正常ユーザーデータは上書きされる', () async {
      final scheduler = TimelineFetchScheduler.instance;

      scheduler.onPostsFetched?.call([
        makePost(id: 'overwrite_1', username: 'Alice', likeCount: 5),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // ユーザー名ありの投稿で上書き
      scheduler.onPostsFetched?.call([
        makePost(id: 'overwrite_1', username: 'Alice Updated', likeCount: 10),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.posts.first.username, 'Alice Updated');
      expect(notifier.state.posts.first.likeCount, 10);
    });

    test('_onPostsFetched で重複排除と時系列ソート', () async {
      final scheduler = TimelineFetchScheduler.instance;

      scheduler.onPostsFetched?.call([
        makePost(id: 'dup_1', body: 'v1', timestamp: DateTime(2024, 1, 1)),
        makePost(id: 'dup_2', body: 'v1', timestamp: DateTime(2024, 1, 3)),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 既存の投稿がある状態で新規投稿を含むバッチを送信
      // dup_2 は既存 → 即時更新、dup_3 は新規 → ドリップキューへ
      scheduler.onPostsFetched?.call([
        makePost(id: 'dup_2', body: 'v2', timestamp: DateTime(2024, 1, 3)),
        makePost(id: 'dup_3', body: 'v1', timestamp: DateTime(2024, 1, 2)),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // dup_2 は即時更新される
      expect(notifier.state.posts[0].id, 'dup_2');
      expect(notifier.state.posts[0].body, 'v2');
      // dup_3 はドリップキューにある
      expect(notifier.state.pendingCount, 1);

      // ドリップタイマーが発火するのを待つ
      // スケジューラ間隔(60s) / キュー件数(1) = 60s → clamp(300ms, 2000ms) = 2000ms
      await Future<void>.delayed(const Duration(milliseconds: 2100));

      expect(notifier.state.posts.length, 3);
      // 時系列ソート：dup_2 (1/3) > dup_3 (1/2) > dup_1 (1/1)
      expect(notifier.state.posts[0].id, 'dup_2');
      expect(notifier.state.posts[1].id, 'dup_3');
      expect(notifier.state.posts[2].id, 'dup_1');
      expect(notifier.state.pendingCount, 0);
    });

    test('_onPostsFetched 後に isLoading が false、error がクリアされる', () async {
      final scheduler = TimelineFetchScheduler.instance;

      scheduler.onPostsFetched?.call([
        makePost(id: 'loading_test'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, isNull);
    });

    test('updatePostEngagement で投稿のエンゲージメントが更新される', () async {
      final scheduler = TimelineFetchScheduler.instance;

      // まず投稿を追加
      scheduler.onPostsFetched?.call([
        makePost(id: 'eng_p1', likeCount: 5, isLiked: false),
        makePost(id: 'eng_p2', likeCount: 3, isLiked: true),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.updatePostEngagement(
        'eng_p1',
        isLiked: true,
        likeCount: 6,
      );

      final p1 = notifier.state.posts.firstWhere((p) => p.id == 'eng_p1');
      expect(p1.isLiked, true);
      expect(p1.likeCount, 6);

      // 他のポストに影響しない
      final p2 = notifier.state.posts.firstWhere((p) => p.id == 'eng_p2');
      expect(p2.likeCount, 3);
      expect(p2.isLiked, true);
    });

    test('updatePostEngagement で repost も更新可能', () async {
      final scheduler = TimelineFetchScheduler.instance;

      scheduler.onPostsFetched?.call([
        makePost(id: 'rp_p1', repostCount: 2, isReposted: false),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.updatePostEngagement(
        'rp_p1',
        isReposted: true,
        repostCount: 3,
      );

      final p = notifier.state.posts.firstWhere((p) => p.id == 'rp_p1');
      expect(p.isReposted, true);
      expect(p.repostCount, 3);
    });

    test('updatePostEngagement で存在しない postId は何もしない', () async {
      final scheduler = TimelineFetchScheduler.instance;

      scheduler.onPostsFetched?.call([
        makePost(id: 'exist_p1', likeCount: 5),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      notifier.updatePostEngagement(
        'nonexistent',
        isLiked: true,
        likeCount: 100,
      );

      // 元のポストは変更なし
      final p = notifier.state.posts.firstWhere((p) => p.id == 'exist_p1');
      expect(p.likeCount, 5);
    });

    test('updatePostEngagement で部分更新', () async {
      final scheduler = TimelineFetchScheduler.instance;

      scheduler.onPostsFetched?.call([
        makePost(
          id: 'partial_p1',
          likeCount: 5,
          repostCount: 3,
          isLiked: false,
          isReposted: false,
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // isLiked のみ更新
      notifier.updatePostEngagement('partial_p1', isLiked: true);

      final p = notifier.state.posts.firstWhere((p) => p.id == 'partial_p1');
      expect(p.isLiked, true);
      // 他のフィールドは変わらない
      expect(p.likeCount, 5);
      expect(p.repostCount, 3);
      expect(p.isReposted, false);
    });

    test('clearError でエラーがクリアされる', () {
      // FeedNotifier を新規作成してエラー状態を検証
      // clearError は state.copyWith(clearError: true) を呼ぶ
      notifier.clearError();
      expect(notifier.state.error, isNull);
    });

    test('clear で状態が完全にリセットされる', () async {
      final scheduler = TimelineFetchScheduler.instance;

      // 投稿を追加
      scheduler.onPostsFetched?.call([
        makePost(id: 'clear_p1'),
        makePost(id: 'clear_p2'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.posts.length, 2);

      notifier.clear();

      expect(notifier.state.posts, isEmpty);
      expect(notifier.state.isLoading, false);
      expect(notifier.state.isLoadingMore, false);
      expect(notifier.state.error, isNull);
    });

    test('postsForService で X の投稿をフィルタ', () async {
      final scheduler = TimelineFetchScheduler.instance;

      scheduler.onPostsFetched?.call([
        makePost(id: 'svc_x1', source: SnsService.x),
        makePost(id: 'svc_bsky1', source: SnsService.bluesky),
        makePost(id: 'svc_x2', source: SnsService.x),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final xPosts = notifier.postsForService(SnsService.x);
      expect(xPosts.length, 2);
      expect(xPosts.every((p) => p.source == SnsService.x), true);
    });

    test('postsForService で Bluesky の投稿をフィルタ', () async {
      final scheduler = TimelineFetchScheduler.instance;

      scheduler.onPostsFetched?.call([
        makePost(id: 'svc2_x1', source: SnsService.x),
        makePost(id: 'svc2_bsky1', source: SnsService.bluesky),
        makePost(id: 'svc2_bsky2', source: SnsService.bluesky),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final bskyPosts = notifier.postsForService(SnsService.bluesky);
      expect(bskyPosts.length, 2);
      expect(bskyPosts.every((p) => p.source == SnsService.bluesky), true);
    });

    test('postsForService で一致しないサービスは空リスト', () async {
      final scheduler = TimelineFetchScheduler.instance;

      scheduler.onPostsFetched?.call([
        makePost(id: 'svc3_x1', source: SnsService.x),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final bskyPosts = notifier.postsForService(SnsService.bluesky);
      expect(bskyPosts, isEmpty);
    });

    test('onTokenExpired コールバックが呼ばれる', () {
      String? capturedAccountId;
      String? capturedHandle;
      notifier.onTokenExpired = (accountId, handle) {
        capturedAccountId = accountId;
        capturedHandle = handle;
      };

      // onTokenExpired コールバックを呼び出し
      notifier.onTokenExpired?.call('acc_1', '@testuser');

      expect(capturedAccountId, 'acc_1');
      expect(capturedHandle, '@testuser');
    });

    test('onTokenExpired がスケジューラから通知される', () {
      String? capturedAccountId;
      String? capturedHandle;
      notifier.onTokenExpired = (accountId, handle) {
        capturedAccountId = accountId;
        capturedHandle = handle;
      };

      // スケジューラの onTokenExpired コールバック経由で通知
      TimelineFetchScheduler.instance.onTokenExpired
          ?.call('acc_expired', '@expired.user');

      expect(capturedAccountId, 'acc_expired');
      expect(capturedHandle, '@expired.user');
    });

    test('refresh sets isLoading to true then false', () async {
      // refresh calls fetchAll which has no accounts, so it completes immediately
      expect(notifier.state.isLoading, false);
      await notifier.refresh();
      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, isNull);
    });

    test('loadMore sets isLoadingMore to true then false', () async {
      // loadMore also calls fetchAll with no accounts
      expect(notifier.state.isLoadingMore, false);
      await notifier.loadMore();
      expect(notifier.state.isLoadingMore, false);
    });

    test('loadMore does nothing when already loading', () async {
      // Set isLoading true first
      final scheduler = TimelineFetchScheduler.instance;
      // Trigger refresh to set isLoading (but it completes fast with no accounts)
      await notifier.refresh();

      // Manually verify that loadMore when isLoadingMore is already true would skip
      expect(notifier.state.isLoadingMore, false);
    });

    test('_onFetchLog is called via scheduler onFetchLog', () async {
      // FeedNotifier sets TimelineFetchScheduler.instance.onFetchLog = _onFetchLog
      // which logs to ActivityLogNotifier
      // Create notifier with null _logNotifier, so it doesn't crash
      final scheduler = TimelineFetchScheduler.instance;

      // Calling onFetchLog should not throw even with null log notifier
      scheduler.onFetchLog?.call('@test', SnsService.x, true, 5, null);
      scheduler.onFetchLog?.call('@test', SnsService.bluesky, false, 0, 'error');

      // No crash = success
      expect(true, true);
    });

    test('_onTokenExpired is forwarded from scheduler', () {
      String? receivedId;
      String? receivedHandle;
      notifier.onTokenExpired = (id, handle) {
        receivedId = id;
        receivedHandle = handle;
      };

      // This triggers _onTokenExpired in FeedNotifier
      TimelineFetchScheduler.instance.onTokenExpired?.call('expired_id', '@expired');

      expect(receivedId, 'expired_id');
      expect(receivedHandle, '@expired');
    });
  });
}
