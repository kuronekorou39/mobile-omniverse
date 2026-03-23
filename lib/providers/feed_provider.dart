import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';
import '../providers/settings_provider.dart';
import '../services/timeline_cache_service.dart';
import '../services/timeline_fetch_scheduler.dart';
import '../utils/image_headers.dart';

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
  FeedNotifier(this._logNotifier, this._settingsReader) : super(const FeedState()) {
    TimelineFetchScheduler.instance.onPostsFetched = _onPostsFetched;
    TimelineFetchScheduler.instance.onFetchStart = _onFetchStart;
    TimelineFetchScheduler.instance.onFetchLog = _onFetchLog;
    TimelineFetchScheduler.instance.onTokenExpired = _onTokenExpired;
    _loadCachedTimeline();
    _listenToOverlayCommands();
    _startCountdownTimer();
    // スケジューラが既に動いている場合、コールバック登録後に初回フェッチをトリガー
    if (TimelineFetchScheduler.instance.isRunning) {
      Future.microtask(() => TimelineFetchScheduler.instance.fetchAll());
    }
  }

  /// ドリップ→バナー切替の閾値（フェッチ間隔秒数と同じ）
  int get dripThreshold => _settingsReader().fetchIntervalSeconds;

  final List<Post> _pendingQueue = [];
  final Set<String> _pendingIds = {};
  Timer? _dripTimer;
  Timer? _dripDelayTimer;
  Timer? _countdownTimer;
  bool _bypassDrip = false;
  bool _firstFetch = true;
  bool _isAtTop = true;
  int _remainingSeconds = 0;
  bool _wasFetching = false;
  final SettingsState Function() _settingsReader;

  /// 画像キャッシュ済みの投稿 ID
  final Set<String> _precachedIds = {};

  /// 投稿の画像をプリキャッシュ
  Future<void> _precachePostImages(Post post) async {
    if (_precachedIds.contains(post.id)) return;
    final urls = <String>[
      if (post.avatarUrl != null) post.avatarUrl!,
      ...post.imageUrls,
      if (post.videoThumbnailUrl != null) post.videoThumbnailUrl!,
    ];
    if (urls.isEmpty) {
      _precachedIds.add(post.id);
      return;
    }
    try {
      debugPrint('[Feed] Precaching ${urls.length} images for ${post.id}');
      await Future.wait(
        urls.map((url) => DefaultCacheManager().downloadFile(
              url,
              authHeaders: kImageHeaders,
            )),
      ).timeout(const Duration(seconds: 5), onTimeout: () => []);
      debugPrint('[Feed] Precache done for ${post.id}');
    } catch (e) {
      debugPrint('[Feed] Precache error for ${post.id}: $e');
    }
    _precachedIds.add(post.id);
  }

  /// 複数投稿の画像を並列プリキャッシュ
  void _precachePostsImages(List<Post> posts) {
    debugPrint('[Feed] Starting precache for ${posts.length} posts');
    for (final post in posts) {
      _precachePostImages(post);
    }
  }

  /// トークン期限切れアカウントの通知用 (accountId, handle)
  void Function(String accountId, String handle)? onTokenExpired;

  void _listenToOverlayCommands() {
    FlutterOverlayWindow.setMainAppCommandHandler((message) {
      if (message is Map) {
        final cmd = message['cmd'];
        if (cmd == 'refresh') {
          refresh();
        } else if (cmd == 'loadMore') {
          loadMore();
        }
      }
    });
  }

  void _onTokenExpired(String accountId, String handle) {
    onTokenExpired?.call(accountId, handle);
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      // フェッチ完了時にカウントダウンをリセット
      if (_wasFetching && !state.isFetching) {
        _remainingSeconds = _settingsReader().fetchIntervalSeconds;
      }
      _wasFetching = state.isFetching;

      if (!state.isFetching && _remainingSeconds > 0) {
        _remainingSeconds--;
      }

      // オーバーレイにタイマー状態を同期
      _syncToOverlay();
    });
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

  Future<void> _syncToOverlay() async {
    try {
      final isActive = await FlutterOverlayWindow.isActive();
      if (!isActive) return;
      final settings = _settingsReader();
      final hideRtIds = settings.hideRetweetsAccountIds;
      var visiblePosts = state.posts.where((p) =>
          !p.isRetweet ||
          p.fetchedByAccountIds.isEmpty ||
          p.fetchedByAccountIds.any((id) => !hideRtIds.contains(id)));
      final posts = visiblePosts.take(100).map((p) => p.toJson()).toList();
      final total = settings.fetchIntervalSeconds;
      final payload = {
        'posts': posts,
        'fetch': {
          'remaining': state.isFetching ? 0 : _remainingSeconds.clamp(0, total),
          'total': total,
          'isFetching': state.isFetching,
        },
        'showFetchTimer': settings.showFetchTimer,
      };
      await FlutterOverlayWindow.shareData(jsonEncode(payload));
    } catch (_) {}
  }

  /// ユーザー情報が欠けているかを判定
  static bool _isUserDataMissing(Post post) {
    return post.username.isEmpty || post.handle == '@';
  }

  void _onFetchStart() {
    _remainingSeconds = 0;
    state = state.copyWith(isFetching: true);
    _syncToOverlay();
  }

  void _onPostsFetched(List<Post> newPosts) {
    final existing = Map<String, Post>.fromEntries(
      state.posts.map((p) => MapEntry(p.id, p)),
    );

    // RT追跡ログ
    final rtBefore = existing.values.where((p) => p.isRetweet).toList();
    debugPrint('[Feed] _onPostsFetched: before=${existing.length} posts, ${rtBefore.length} RTs, newPosts=${newPosts.length}');

    final newToQueue = <String, Post>{};

    for (final post in newPosts) {
      final old = existing[post.id];
      // 取得元アカウントIDをマージ
      final mergedAccountIds = old != null
          ? {...old.fetchedByAccountIds, ...post.fetchedByAccountIds}
          : post.fetchedByAccountIds;
      if (old != null && _isUserDataMissing(post) && !_isUserDataMissing(old)) {
        // ユーザー情報が欠けた投稿で正常なデータを上書きしない — 即時更新
        existing[post.id] = old.copyWith(
          isLiked: post.isLiked,
          isReposted: post.isReposted,
          likeCount: post.likeCount,
          repostCount: post.repostCount,
          fetchedByAccountIds: mergedAccountIds,
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
          fetchedByAccountIds: mergedAccountIds,
        );
      } else if (old != null && old.isRetweet && !post.isRetweet) {
        // RT版が既にあるのに非RT版が来た場合、RTフラグ＋タイムスタンプを保持
        // (同じツイートがRT版と直接版の両方でフェッチされるケース)
        existing[post.id] = post.copyWith(
          fetchedByAccountIds: mergedAccountIds,
          isRetweet: true,
          retweetedByUsername: old.retweetedByUsername,
          retweetedByHandle: old.retweetedByHandle,
          timestamp: old.timestamp, // RT時刻を保持
        );
      } else if (old != null) {
        // 既存投稿の更新（エンゲージメント等）— 即時反映
        if (old.isRetweet && !post.isRetweet) {
          // 安全策: このパスに到達すべきではないがRT保護
          debugPrint('[Feed] WARNING: RT flag lost at general update for ${post.id} (old.isRT=${old.isRetweet}, new.isRT=${post.isRetweet})');
          existing[post.id] = post.copyWith(
            fetchedByAccountIds: mergedAccountIds,
            isRetweet: true,
            retweetedByUsername: old.retweetedByUsername,
            retweetedByHandle: old.retweetedByHandle,
            timestamp: old.timestamp, // RT時刻を保持
          );
        } else {
          existing[post.id] = post.copyWith(fetchedByAccountIds: mergedAccountIds);
        }
      } else if (!_pendingIds.contains(post.id)) {
        // 新規投稿（キューにも未登録）— キューに追加
        // 同一バッチ内でRT版と非RT版が競合する場合、RT版を優先
        final queued = newToQueue[post.id];
        if (queued != null && queued.isRetweet && !post.isRetweet) {
          // RT版が既にキューにあるので非RT版では上書きしない
        } else {
          newToQueue[post.id] = post;
        }
      }
    }

    final newPending = newToQueue.values.toList();

    // 初回ロード・手動リフレッシュ・loadMore・起動後初回フェッチはドリップせず即時反映
    final shouldBypassDrip = _bypassDrip || _firstFetch || state.posts.isEmpty;
    _bypassDrip = false;
    _firstFetch = false;

    if (shouldBypassDrip && newPending.isNotEmpty) {
      _precachePostsImages(newPending);
      for (final post in newPending) {
        existing[post.id] = post;
      }
    }

    // RT消失チェック
    final rtAfter = existing.values.where((p) => p.isRetweet).toList();
    if (rtAfter.length < rtBefore.length) {
      debugPrint('[Feed] ⚠️ RT LOST: ${rtBefore.length} → ${rtAfter.length}');
      for (final rt in rtBefore) {
        final current = existing[rt.id];
        if (current == null) {
          debugPrint('[Feed]   MISSING: ${rt.id} by ${rt.retweetedByUsername}');
        } else if (!current.isRetweet) {
          debugPrint('[Feed]   FLAG LOST: ${rt.id} was RT, now not RT (accountId=${current.accountId}, fetchedBy=${current.fetchedByAccountIds})');
        }
      }
    }
    debugPrint('[Feed] _onPostsFetched: after=${existing.length} posts, ${rtAfter.length} RTs, bypass=$shouldBypassDrip, newPending=${newPending.length}');

    // 既存投稿の即時更新を反映
    final sorted = existing.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    state = state.copyWith(posts: sorted, isLoading: false, isFetching: false, clearError: true);

    // キューから既に表示済みの投稿を除去（フェッチ間にドリップされた分など）
    if (_pendingQueue.isNotEmpty) {
      final currentIds = state.posts.map((p) => p.id).toSet();
      final beforeLen = _pendingQueue.length;
      _pendingQueue.removeWhere((p) => currentIds.contains(p.id));
      _pendingIds.removeWhere((id) => currentIds.contains(id));
      if (_pendingQueue.length != beforeLen) {
        debugPrint('[Feed] Queue cleanup: $beforeLen → ${_pendingQueue.length}');
        state = state.copyWith(pendingCount: _pendingQueue.length);
      }
    }

    // 新規投稿をキューに追加（ドリップ対象の場合のみ）
    if (!shouldBypassDrip && newPending.isNotEmpty) {
      // RT非表示フィルタ + state.posts/キュー重複フィルタ
      final hideRtIds = _settingsReader().hideRetweetsAccountIds;
      final stateIds = state.posts.map((p) => p.id).toSet();
      final filtered = newPending
          .where((p) =>
              !stateIds.contains(p.id) &&
              !_pendingIds.contains(p.id) &&
              !(p.isRetweet &&
                p.fetchedByAccountIds.isNotEmpty &&
                p.fetchedByAccountIds.every((id) => hideRtIds.contains(id))))
          .toList();
      debugPrint('[Feed] newPending=${newPending.length} filtered=${filtered.length} (hideRT=${hideRtIds.length})');
      if (filtered.isEmpty) return;
      _precachePostsImages(filtered);
      _pendingQueue.addAll(filtered);
      _pendingIds.addAll(filtered.map((p) => p.id));
      state = state.copyWith(pendingCount: _pendingQueue.length);
      if (_pendingQueue.length <= dripThreshold) {
        _startDrip();
      } else {
        // 大量の場合はドリップ停止 → バナーモード
        _dripTimer?.cancel();
        _dripTimer = null;
      }
    }

    // バックグラウンドでキャッシュ保存
    TimelineCacheService.instance.saveTimeline(sorted);

    // オーバーレイへ同期
    _syncToOverlay();
  }

  void _startDrip() {
    _dripTimer?.cancel();
    if (_pendingQueue.isEmpty) return;
    if (_pendingQueue.length > dripThreshold) return; // バナーモードではドリップしない

    // 古い順にソート → 各ドリップが常にリスト先頭に挿入されるように
    _pendingQueue.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // フェッチ間隔 ÷ キュー件数 (300ms〜2000ms)
    final schedulerIntervalMs =
        TimelineFetchScheduler.instance.interval.inMilliseconds;
    final intervalMs =
        (schedulerIntervalMs / _pendingQueue.length).round().clamp(200, 3000);
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

    // 重複をスキップして最初の有効な投稿を見つける
    Post? post;
    while (_pendingQueue.isNotEmpty) {
      final candidate = _pendingQueue.removeAt(0);
      _pendingIds.remove(candidate.id);
      if (!state.posts.any((p) => p.id == candidate.id)) {
        post = candidate;
        break;
      }
    }
    if (post == null) {
      // 全て重複だった
      state = state.copyWith(pendingCount: _pendingQueue.length);
      if (_pendingQueue.isEmpty) {
        _dripTimer?.cancel();
        _dripTimer = null;
      }
      return;
    }

    // 常にリスト先頭に挿入（古い順ドリップなので最終的に新しい順になる）
    final posts = List<Post>.of(state.posts);
    posts.insert(0, post);

    state = state.copyWith(posts: posts, pendingCount: _pendingQueue.length);

    // キャッシュ更新
    TimelineCacheService.instance.saveTimeline(posts);

    // オーバーレイへ同期
    _syncToOverlay();
  }

  /// バナーモード: 溜まった投稿を一括でタイムラインに反映
  void flushPending() {
    if (_pendingQueue.isEmpty) return;
    _dripTimer?.cancel();
    _dripTimer = null;

    final existing = Map<String, Post>.fromEntries(
      state.posts.map((p) => MapEntry(p.id, p)),
    );
    for (final post in _pendingQueue) {
      existing[post.id] = post;
    }
    _pendingQueue.clear();
    _pendingIds.clear();

    final sorted = existing.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    state = state.copyWith(posts: sorted, pendingCount: 0);

    TimelineCacheService.instance.saveTimeline(sorted);
    _syncToOverlay();
  }

  List<Post> postsForService(SnsService service) {
    return state.posts.where((p) => p.source == service).toList();
  }

  Future<void> refresh() async {
    _bypassDrip = true;
    _pendingQueue.clear();
    _pendingIds.clear();
    _dripTimer?.cancel();
    _dripTimer = null;
    state = state.copyWith(isLoading: true, pendingCount: 0, clearError: true);
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
    _countdownTimer?.cancel();
    FlutterOverlayWindow.setMainAppCommandHandler(null);
    super.dispose();
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>(
  (ref) {
    final logNotifier = ref.read(activityLogProvider.notifier);
    return FeedNotifier(logNotifier, () => ref.read(settingsProvider));
  },
);
