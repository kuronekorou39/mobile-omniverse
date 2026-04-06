import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';
import '../providers/fetch_status_provider.dart';
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
  @override
  set state(FeedState value) {
    // 投稿リストが変わったらオーバーレイ同期フラグを立てる
    if (!identical(value.posts, super.state.posts)) {
      _overlayPostsDirty = true;
    }
    super.state = value;
  }

  FeedNotifier(this._logNotifier, this._settingsReader, this._fetchStatusNotifier) : super(const FeedState()) {
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

  /// タイムラインの投稿保持上限（これを超えた古い投稿は破棄）
  static const int _maxPosts = 500;

  /// キャッシュ保存カウンター（毎回ではなく数回に1回保存）
  int _cacheSaveCounter = 0;
  static const int _cacheSaveEveryN = 5;

  final List<Post> _pendingQueue = [];
  final Set<String> _pendingIds = {};
  Timer? _dripTimer;
  Timer? _dripDelayTimer;
  Timer? _countdownTimer;
  bool _bypassDrip = false;
  bool _firstFetch = true;
  bool _isAtTop = true;
  bool _overlayActive = false;
  bool _overlayAtTop = true;
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
    // キャッシュID上限を超えたら古いものを削除
    if (_precachedIds.length > _maxPosts * 2) {
      final excess = _precachedIds.length - _maxPosts;
      _precachedIds.removeAll(_precachedIds.take(excess).toList());
    }
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
        } else if (cmd == 'close') {
          setOverlayActive(false);
        } else if (cmd == 'overlayScrollAtTop') {
          setOverlayScrollAtTop(message['atTop'] as bool? ?? true);
        }
      }
    });
  }

  void _onTokenExpired(String accountId, String handle) {
    _fetchStatusNotifier?.setExpired(accountId);
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
  final FetchStatusNotifier? _fetchStatusNotifier;

  void _onFetchLog(String accountId, String accountHandle, SnsService platform,
      bool success, int postCount, String? error) {
    _logNotifier?.logAction(
      action: ActivityAction.timelineFetch,
      platform: platform,
      accountHandle: accountHandle,
      success: success,
      targetSummary: success ? '$postCount 件取得' : null,
      errorMessage: error,
    );
    _fetchStatusNotifier?.update(accountId, success);
  }

  /// 投稿リストの変更フラグ（trueなら次の同期でフルデータを送信）
  bool _overlayPostsDirty = true;

  /// 投稿リストを上限に切り詰め、古い投稿のキャッシュIDも解放
  List<Post> _trimPosts(List<Post> posts) {
    if (posts.length <= _maxPosts) return posts;
    final removed = posts.sublist(_maxPosts);
    for (final p in removed) {
      _precachedIds.remove(p.id);
    }
    return posts.sublist(0, _maxPosts);
  }

  /// 毎秒のタイマー同期（タイマー情報のみ、投稿変更時のみフルデータ）
  Future<void> _syncToOverlay() async {
    try {
      if (!_overlayActive) return;
      final settings = _settingsReader();
      final total = settings.fetchIntervalSeconds;
      final payload = <String, dynamic>{
        'fetch': {
          'remaining': state.isFetching ? 0 : _remainingSeconds.clamp(0, total),
          'total': total,
          'isFetching': state.isFetching,
        },
        'showFetchTimer': settings.showFetchTimer,
        'hideUserInfo': settings.hideUserInfo,
      };

      // 投稿に変更があった場合のみフルデータを送信
      if (_overlayPostsDirty) {
        _overlayPostsDirty = false;
        final hideRtIds = settings.hideRetweetsAccountIds;
        var visiblePosts = state.posts.where((p) =>
            !p.isRetweet ||
            p.fetchedByAccountIds.isEmpty ||
            p.fetchedByAccountIds.any((id) => !hideRtIds.contains(id)));
        payload['posts'] = visiblePosts.take(100).map((p) => p.toJson()).toList();
      }

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
  }

  void _onPostsFetched(List<Post> newPosts) {
    // アニメーションフレーム間で処理（idleだと起動直後に実行されない）
    SchedulerBinding.instance.scheduleTask(
        () => _processNewPosts(newPosts), Priority.animation);
  }

  void _processNewPosts(List<Post> newPosts) {
    final existing = Map<String, Post>.fromEntries(
      state.posts.map((p) => MapEntry(p.id, p)),
    );

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
        final queued = newToQueue[post.id];
        if (queued != null) {
          // 同一バッチ内の重複: fetchedByAccountIdsをマージ
          final mergedIds = {...queued.fetchedByAccountIds, ...post.fetchedByAccountIds};
          if (queued.isRetweet && !post.isRetweet) {
            // RT版が既にキューにあるので非RT版では上書きしない（IDマージのみ）
            newToQueue[post.id] = queued.copyWith(fetchedByAccountIds: mergedIds);
          } else {
            newToQueue[post.id] = post.copyWith(fetchedByAccountIds: mergedIds);
          }
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

    // 既存投稿の即時更新を反映
    final sorted = _trimPosts(existing.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));

    // IDセットを1回だけ計算（複数箇所で再利用）
    final sortedIds = sorted.map((p) => p.id).toSet();

    // キューから既に表示済みの投稿を除去
    if (_pendingQueue.isNotEmpty) {
      _pendingQueue.removeWhere((p) => sortedIds.contains(p.id));
      _pendingIds.removeWhere((id) => sortedIds.contains(id));
    }

    // 新規投稿のキュー処理（ドリップ対象の場合のみ）
    int newPendingCount = _pendingQueue.length;
    if (!shouldBypassDrip && newPending.isNotEmpty) {
      final hideRtIds = _settingsReader().hideRetweetsAccountIds;
      final filtered = newPending
          .where((p) =>
              !sortedIds.contains(p.id) &&
              !_pendingIds.contains(p.id) &&
              !(p.isRetweet &&
                p.fetchedByAccountIds.isNotEmpty &&
                p.fetchedByAccountIds.every((id) => hideRtIds.contains(id))))
          .toList();

      if (filtered.isNotEmpty) {
        // 古い投稿を分離: タイムライン先頭より古い投稿はドリップせず直接挿入
        final topTimestamp = sorted.isNotEmpty ? sorted.first.timestamp : null;
        final drippable = <Post>[];
        for (final p in filtered) {
          if (topTimestamp != null && p.timestamp.isBefore(topTimestamp)) {
            // 古い投稿はsortedに直接追加
            sorted.add(p);
          } else {
            drippable.add(p);
          }
        }

        if (sorted.length != sortedIds.length + (filtered.length - drippable.length)) {
          // stale投稿が追加された場合のみ再ソート
          sorted.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }

        if (drippable.isNotEmpty) {
          _precachePostsImages(drippable);
          _pendingQueue.addAll(drippable);
          _pendingIds.addAll(drippable.map((p) => p.id));
        }

        newPendingCount = _pendingQueue.length;
      }
    }

    // 新規投稿の追加/削除があったかチェック（先頭IDか件数が変わった場合のみ更新）
    // エンゲージメント更新(いいね数等)はupdatePostEngagement()で個別に反映される
    final oldPosts = state.posts;
    final postsChanged = sorted.length != oldPosts.length ||
        (sorted.isNotEmpty && oldPosts.isNotEmpty &&
            sorted.first.id != oldPosts.first.id);

    state = state.copyWith(
      posts: postsChanged ? sorted : null,
      isLoading: false,
      isFetching: false,
      clearError: true,
      pendingCount: newPendingCount,
    );


    // ドリップ開始判定（メインかオーバーレイのどちらかがトップにいれば開始）
    if (_pendingQueue.isNotEmpty && _dripTimer == null) {
      final canDrip = _isAtTop || (_overlayActive && _overlayAtTop);
      if (canDrip) {
        if (_pendingQueue.length <= dripThreshold) {
          _startDrip();
        } else {
          // 閾値超えでもトップにいるなら自動flush
          flushPending();
        }
      }
    }

    // オーバーレイ同期は次フレームに遅延
    Future.microtask(() => _syncToOverlay());
    // キャッシュ保存は数回に1回（150件のJSON化がメインスレッドをブロックするため）
    _cacheSaveCounter++;
    if (_cacheSaveCounter >= _cacheSaveEveryN) {
      _cacheSaveCounter = 0;
      Future.delayed(const Duration(seconds: 2), () {
        TimelineCacheService.instance.saveTimeline(sorted);
      });
    }
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

  void setOverlayActive(bool active) {
    _overlayActive = active;
    if (!active) _overlayAtTop = true;
    // オーバーレイ表示時トップにいればドリップ再開
    if (active && _overlayAtTop && _pendingQueue.isNotEmpty && _dripTimer == null) {
      _startDrip();
    }
  }

  void setOverlayScrollAtTop(bool atTop) {
    _overlayAtTop = atTop;
    // オーバーレイでトップに戻ったらドリップ再開
    if (_overlayActive && atTop && _pendingQueue.isNotEmpty && _dripTimer == null) {
      _startDrip();
    }
  }

  void setScrollAtTop(bool atTop) {
    _dripDelayTimer?.cancel();
    if (atTop) {
      // 少し待ってからドリップ再開
      _dripDelayTimer = Timer(const Duration(milliseconds: 500), () {
        _isAtTop = true;
        // トップに戻ったらドリップ再開
        if (_pendingQueue.isNotEmpty && _dripTimer == null) {
          if (_pendingQueue.length <= dripThreshold) {
            _startDrip();
          } else {
            flushPending();
          }
        }
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
    // メインもオーバーレイもトップにいないならスキップ
    final overlayReady = _overlayActive && _overlayAtTop;
    if (!_isAtTop && !overlayReady) return;
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

    // タイムスタンプ順の正しい位置に挿入（古い投稿がトップに出て消える問題を防止）
    final posts = List<Post>.of(state.posts);
    int insertIndex = 0;
    while (insertIndex < posts.length &&
        posts[insertIndex].timestamp.isAfter(post.timestamp)) {
      insertIndex++;
    }
    posts.insert(insertIndex, post);

    state = state.copyWith(posts: posts, pendingCount: _pendingQueue.length);

    // キャッシュ更新
    TimelineCacheService.instance.saveTimeline(posts);

    // オーバーレイへ同期
    _syncToOverlay();
  }

  /// ペンディングキューに投稿があるか
  bool get hasPending => _pendingQueue.isNotEmpty;

  /// プルリフレッシュ用: ペンディングの一部を読み込み（位置維持用）
  int flushPendingBatch([int count = 20]) {
    if (_pendingQueue.isEmpty) return 0;
    _dripTimer?.cancel();

    // 新しい順にソートしてから先頭N件を取り出す
    _pendingQueue.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final batch = _pendingQueue.take(count).toList();
    for (final p in batch) {
      _pendingQueue.remove(p);
      _pendingIds.remove(p.id);
    }

    final existing = Map<String, Post>.fromEntries(
      state.posts.map((p) => MapEntry(p.id, p)),
    );
    for (final post in batch) {
      existing[post.id] = post;
    }

    final sorted = _trimPosts(existing.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
    state = state.copyWith(posts: sorted, pendingCount: _pendingQueue.length);

    TimelineCacheService.instance.saveTimeline(sorted);
    _syncToOverlay();

    // ペンディングが残っていてドリップ閾値以下ならドリップ再開
    if (_pendingQueue.isNotEmpty && _pendingQueue.length <= dripThreshold) {
      _startDrip();
    }

    return batch.length;
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

    final sorted = _trimPosts(existing.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
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
    final fetchStatusNotifier = ref.read(fetchStatusProvider.notifier);
    return FeedNotifier(logNotifier, () => ref.read(settingsProvider), fetchStatusNotifier);
  },
);
