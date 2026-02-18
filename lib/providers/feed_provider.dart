import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/post.dart';
import '../models/sns_service.dart';
import '../services/timeline_fetch_scheduler.dart';

class FeedState {
  const FeedState({
    this.posts = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Post> posts;
  final bool isLoading;
  final String? error;

  FeedState copyWith({
    List<Post>? posts,
    bool? isLoading,
    String? error,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
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

    state = state.copyWith(posts: sorted, isLoading: false);
  }

  List<Post> postsForService(SnsService service) {
    return state.posts.where((p) => p.source == service).toList();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await TimelineFetchScheduler.instance.fetchAll();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clear() {
    state = const FeedState();
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>(
  (ref) => FeedNotifier(),
);
