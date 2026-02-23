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
    this.error,
  });

  final List<Post> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  FeedState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class FeedNotifier extends StateNotifier<FeedState> {
  FeedNotifier(this._logNotifier) : super(const FeedState()) {
    TimelineFetchScheduler.instance.onPostsFetched = _onPostsFetched;
    TimelineFetchScheduler.instance.onFetchLog = _onFetchLog;
    TimelineFetchScheduler.instance.onTokenExpired = _onTokenExpired;
    _loadCachedTimeline();
  }

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

  void _onPostsFetched(List<Post> newPosts) {
    final existing = Map<String, Post>.fromEntries(
      state.posts.map((p) => MapEntry(p.id, p)),
    );

    for (final post in newPosts) {
      final old = existing[post.id];
      if (old != null && post.username.isEmpty && old.username.isNotEmpty) {
        // ユーザー情報が欠けた投稿で正常なデータを上書きしない
        existing[post.id] = old.copyWith(
          isLiked: post.isLiked,
          isReposted: post.isReposted,
          likeCount: post.likeCount,
          repostCount: post.repostCount,
        );
      } else {
        existing[post.id] = post;
      }
    }

    // 常に時系列順にソート
    final sorted = existing.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    state = state.copyWith(posts: sorted, isLoading: false, clearError: true);

    // バックグラウンドでキャッシュ保存
    TimelineCacheService.instance.saveTimeline(sorted);
  }

  List<Post> postsForService(SnsService service) {
    return state.posts.where((p) => p.source == service).toList();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await TimelineFetchScheduler.instance.fetchAll();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      // Scheduler handles pagination internally
      await TimelineFetchScheduler.instance.fetchAll();
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
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>(
  (ref) {
    final logNotifier = ref.read(activityLogProvider.notifier);
    return FeedNotifier(logNotifier);
  },
);
