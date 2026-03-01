import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';
import '../services/timeline_cache_service.dart';
import '../services/timeline_fetch_scheduler.dart';

class FeedState {
  const FeedState({
    this.posts = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isFetching = false,
    this.pendingCount = 0,
    this.error,
  });

  final List<Post> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isFetching;
  final int pendingCount;
  final String? error;

  FeedState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isFetching,
    int? pendingCount,
    String? error,
    bool clearError = false,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isFetching: isFetching ?? this.isFetching,
      pendingCount: pendingCount ?? this.pendingCount,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class FeedNotifier extends StateNotifier<FeedState> {
  FeedNotifier(this._logNotifier) : super(const FeedState()) {
    TimelineFetchScheduler.instance.onPostsFetched = _onPostsFetched;
    TimelineFetchScheduler.instance.onFetchStart = _onFetchStart;
    TimelineFetchScheduler.instance.onFetchLog = _onFetchLog;
    TimelineFetchScheduler.instance.onTokenExpired = _onTokenExpired;
    _loadCachedTimeline();
  }

  final List<Post> _pendingQueue = [];
  Timer? _dripTimer;
  Timer? _dripDelayTimer;
  bool _bypassDrip = false;
  bool _firstFetch = true;
  bool _isAtTop = true;

  /// トークン期限切れアカウントの通知用 (accountId, handle)
  void Function(String accountId, String handle)? onTokenExpired;

  void _onTokenExpired(String accountId, String handle) {
    onTokenExpired?.call(accountId, handle);
  }

  Future<void> _loadCachedTimeline() async {
    final cached = await TimelineCacheService.instance.loadCachedTimeline();
    if (cached.isNotEmpty && state.posts.isEmpty) {
      state = state.copyWith(posts: cached);
    }
  }

  final ActivityLogNotifier? _logNotifier;

  void _onFetchLog(String accountHandle, SnsService platform, bool success,
      int postCount, String? error) {
    _logNotifier?.logAction(
      action: ActivityAction.timelineFetch,
      platform: platform,
      accountHandle: accountHandle,
      success: success,
      targetSummary: success ? '$postCount 件取得' : null,
      errorMessage: error,
    );
  }

  /// ユーザー情報が欠けているかを判定
  static bool _isUserDataMissing(Post post) {
    return post.username.isEmpty || post.handle == '@';
  }

  void _onFetchStart() {
    state = state.copyWith(isFetching: true);
  }

  void _onPostsFetched(List<Post> newPosts) {
    final existing = Map<String, Post>.fromEntries(
      state.posts.map((p) => MapEntry(p.id, p)),
    );

    final newToQueue = <Post>[];

    for (final post in newPosts) {
      final old = existing[post.id];
      if (old != null && _isUserDataMissing(post) && !_isUserDataMissing(old)) {
        // ユーザー情報が欠けた投稿で正常なデータを上書きしない — 即時更新
        existing[post.id] = old.copyWith(
          isLiked: post.isLiked,
          isReposted: post.isReposted,
          likeCount: post.likeCount,
          repostCount: post.repostCount,
        );
      } else if (old != null && post.isRetweet && !_isUserDataMissing(old) &&
                 old.retweetedByUsername != null && old.retweetedByUsername!.isNotEmpty &&
                 (post.retweetedByUsername == null || post.retweetedByUsername!.isEmpty)) {
        // RT投稿: リツイーター情報が欠けている場合も保護 — 即時更新
        existing[post.id] = old.copyWith(
          isLiked: post.isLiked,
          isReposted: post.isReposted,
          likeCount: post.likeCount,
          repostCount: post.repostCount,
        );
      } else if (old != null) {
        // 既存投稿の更新（エンゲージメント等）— 即時反映
        existing[post.id] = post;
      } else {
        // 新規投稿 — キューに追加
        newToQueue.add(post);
      }
    }

    // 初回ロード・手動リフレッシュ・loadMore・起動後初回フェッチはドリップせず即時反映
    final shouldBypassDrip = _bypassDrip || _firstFetch || state.posts.isEmpty;
    _bypassDrip = false;
    _firstFetch = false;

    if (shouldBypassDrip && newToQueue.isNotEmpty) {
      for (final post in newToQueue) {
        existing[post.id] = post;
      }
    }

    // 既存投稿の即時更新を反映
    final sorted = existing.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    state = state.copyWith(posts: sorted, isLoading: false, isFetching: false, clearError: true);

    // 新規投稿をキューに追加（ドリップ対象の場合のみ）
    if (!shouldBypassDrip && newToQueue.isNotEmpty) {
      _pendingQueue.addAll(newToQueue);
      state = state.copyWith(pendingCount: _pendingQueue.length);
      _startDrip();
    }

    // バックグラウンドでキャッシュ保存
    TimelineCacheService.instance.saveTimeline(sorted);
  }

  void _startDrip() {
    _dripTimer?.cancel();
    if (_pendingQueue.isEmpty) return;

    // フェッチ間隔 ÷ キュー件数 (300ms〜2000ms)
    final schedulerIntervalMs =
        TimelineFetchScheduler.instance.interval.inMilliseconds;
    final intervalMs =
        (schedulerIntervalMs / _pendingQueue.length).round().clamp(300, 2000);
    _dripTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _dripOne();
    });
  }

  void setScrollAtTop(bool atTop) {
    _dripDelayTimer?.cancel();
    if (atTop) {
      // 少し待ってからドリップ再開
      _dripDelayTimer = Timer(const Duration(milliseconds: 500), () {
        _isAtTop = true;
      });
    } else {
      _isAtTop = false;
    }
  }

  void _dripOne() {
    if (_pendingQueue.isEmpty) {
      _dripTimer?.cancel();
      _dripTimer = null;
      return;
    }
    if (!_isAtTop) return; // トップにいないならスキップ
    if (!mounted) {
      _dripTimer?.cancel();
      _dripTimer = null;
      return;
    }

    final post = _pendingQueue.removeAt(0);

    final existing = Map<String, Post>.fromEntries(
      state.posts.map((p) => MapEntry(p.id, p)),
    );
    existing[post.id] = post;

    final sorted = existing.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    state = state.copyWith(posts: sorted, pendingCount: _pendingQueue.length);

    // キャッシュ更新
    TimelineCacheService.instance.saveTimeline(sorted);
  }

  List<Post> postsForService(SnsService service) {
    return state.posts.where((p) => p.source == service).toList();
  }

  Future<void> refresh() async {
    _bypassDrip = true;
    state = state.copyWith(isLoading: true, clearError: true);
    TimelineFetchScheduler.instance.resetCursors();
    try {
      await TimelineFetchScheduler.instance.fetchAll();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading) return;
    _bypassDrip = true;
    state = state.copyWith(isLoadingMore: true);
    try {
      await TimelineFetchScheduler.instance.fetchMore();
      state = state.copyWith(isLoadingMore: false);
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void updatePostEngagement(
    String postId, {
    bool? isLiked,
    bool? isReposted,
    int? likeCount,
    int? repostCount,
  }) {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;
    final posts = List<Post>.of(state.posts);
    posts[idx] = posts[idx].copyWith(
      isLiked: isLiked,
      isReposted: isReposted,
      likeCount: likeCount,
      repostCount: repostCount,
    );
    state = state.copyWith(posts: posts);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void clear() {
    state = const FeedState();
  }

  @override
  void dispose() {
    _dripTimer?.cancel();
    _dripDelayTimer?.cancel();
    super.dispose();
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>(
  (ref) {
    final logNotifier = ref.read(activityLogProvider.notifier);
    return FeedNotifier(logNotifier);
  },
);
