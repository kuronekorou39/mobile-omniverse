import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../models/sns_service.dart';
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
  FeedNotifier() : super(const FeedState()) {
    TimelineFetchScheduler.instance.onPostsFetched = _onPostsFetched;
  }

  void _onPostsFetched(List<Post> newPosts) {
    final existing = Map<String, Post>.fromEntries(
      state.posts.map((p) => MapEntry(p.id, p)),
    );

    for (final post in newPosts) {
      existing[post.id] = post;
    }

    final sorted = existing.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    state = state.copyWith(posts: sorted, isLoading: false, clearError: true);
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
    final posts = state.posts.map((p) {
      if (p.id == postId) {
        return p.copyWith(
          isLiked: isLiked,
          isReposted: isReposted,
          likeCount: likeCount,
          repostCount: repostCount,
        );
      }
      return p;
    }).toList();
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
  (ref) => FeedNotifier(),
);
