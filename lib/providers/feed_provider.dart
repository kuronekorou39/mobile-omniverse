import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
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
import '../services/memory_guard_service.dart';
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
    this.fastDripActive = false,
    this.error,
  });

  final List<Post> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isFetching;
  final int pendingCount;
  final bool fastDripActive;
  final String? error;

  FeedState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isFetching,
    int? pendingCount,
    bool? fastDripActive,
    String? error,
    bool clearError = false,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isFetching: isFetching ?? this.isFetching,
      pendingCount: pendingCount ?? this.pendingCount,
      fastDripActive: fastDripActive ?? this.fastDripActive,
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

  /// キューの上限（これを超えた古い投稿は切り捨て）
  static const int _maxQueueSize = 1000;

  /// タイムラインの投稿保持上限（これを超えた古い投稿は破棄）
  static const int _maxPosts = 500;

  /// キャッシュ保存カウンター（毎回ではなく数回に1回保存）
  int _cacheSaveCounter = 0;
  static const int _cacheSaveEveryN = 5;

  /// ドリップ中のキャッシュ保存カウンター
  int _dripCacheSaveCounter = 0;
  static const int _dripCacheSaveEveryN = 10;

  final List<Post> _pendingQueue = [];
  final Set<String> _pendingIds = {};
  Timer? _dripTimer;
  Timer? _dripDelayTimer;
  Timer? _countdownTimer;
  bool _bypassDrip = false;
  bool _fastDripActive = false;
  bool _isAtTop = true;
  bool _screenVisible = true;
  bool _overlayActive = false;
  bool _overlayAtTop = true;
  int _remainingSeconds = 0;
  int get remainingSeconds => _remainingSeconds;
  bool _wasFetching = false;
  final SettingsState Function() _settingsReader;

  /// 画像キャッシュ済みの投稿 ID
  final Set<String> _precachedIds = {};

  /// 投稿の画像をプリキャッシュ
  Future<void> _precachePostImages(Post post) async {
    if (_precachedIds.contains(post.id)) return;
    // メモリ警告中はスキップ
    if (MemoryGuardService.instance.isPrecachePaused) {
      _precachedIds.add(post.id);
      return;
    }
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
      // 画像を1枚ずつ順次処理（同時接続数を抑制）
      for (final url in urls) {
        try {
          await DefaultCacheManager().downloadFile(url, authHeaders: kImageHeaders)
              .timeout(const Duration(seconds: 5), onTimeout: () => throw TimeoutException(''));
          await _decodeToMemory(url)
              .timeout(const Duration(seconds: 3), onTimeout: () {});
        } catch (_) {}
      }
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

  /// 画像をFlutterのメモリイメージキャッシュにデコード
  Future<void> _decodeToMemory(String url) async {
    final completer = Completer<void>();
    final provider = CachedNetworkImageProvider(url, headers: kImageHeaders);
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) { if (!completer.isCompleted) completer.complete(); stream.removeListener(listener); },
      onError: (e, _) { if (!completer.isCompleted) completer.complete(); stream.removeListener(listener); },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// 複数投稿の画像を順次プリキャッシュ（同時実行数を制限）
  bool _isPrecaching = false;
  final List<Post> _precacheQueue = [];

  void _precachePostsImages(List<Post> posts) {
    _precacheQueue.addAll(posts.where((p) => !_precachedIds.contains(p.id)));
    if (!_isPrecaching) _processPrecacheQueue();
  }

  Future<void> _processPrecacheQueue() async {
    if (_isPrecaching) return;
    _isPrecaching = true;
    while (_precacheQueue.isNotEmpty) {
      final post = _precacheQueue.removeAt(0);
      await _precachePostImages(post);
    }
    _isPrecaching = false;
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
        'showDripStatus': settings.showDripStatus,
      };

      // 投稿に変更があった場合のみフルデータを送信（トップでない時は保留）
      if (_overlayPostsDirty && _overlayAtTop) {
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

  static bool _engagementChanged(Post old, Post incoming) {
    return !setEquals(old.likedByAccountIds, incoming.likedByAccountIds) ||
        !setEquals(old.repostedByAccountIds, incoming.repostedByAccountIds) ||
        old.likeCount != incoming.likeCount ||
        old.repostCount != incoming.repostCount ||
        old.replyCount != incoming.replyCount;
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
    bool existingUpdated = false;

    for (final post in newPosts) {
      final old = existing[post.id];
      // 取得元アカウントIDをマージ
      final mergedAccountIds = old != null
          ? {...old.fetchedByAccountIds, ...post.fetchedByAccountIds}
          : post.fetchedByAccountIds;
      // エンゲージメント情報をアカウント単位でマージ
      final mergedLikedBy = old != null
          ? {...old.likedByAccountIds, ...post.likedByAccountIds}
          : post.likedByAccountIds;
      final mergedRepostedBy = old != null
          ? {...old.repostedByAccountIds, ...post.repostedByAccountIds}
          : post.repostedByAccountIds;
      final mergedBskyLikeUris = old != null
          ? {...old.bskyLikeUris, ...post.bskyLikeUris}
          : post.bskyLikeUris;
      final mergedBskyRepostUris = old != null
          ? {...old.bskyRepostUris, ...post.bskyRepostUris}
          : post.bskyRepostUris;
      if (old != null && _isUserDataMissing(post) && !_isUserDataMissing(old)) {
        // ユーザー情報が欠けた投稿で正常なデータを上書きしない — 即時更新
        if (!existingUpdated) {
          existingUpdated = _engagementChanged(old, post);
        }
        existing[post.id] = old.copyWith(
          likedByAccountIds: mergedLikedBy,
          repostedByAccountIds: mergedRepostedBy,
          bskyLikeUris: mergedBskyLikeUris,
          bskyRepostUris: mergedBskyRepostUris,
          likeCount: post.likeCount,
          repostCount: post.repostCount,
          fetchedByAccountIds: mergedAccountIds,
        );
      } else if (old != null && post.isRetweet && !_isUserDataMissing(old) &&
                 old.retweetedByUsername != null && old.retweetedByUsername!.isNotEmpty &&
                 (post.retweetedByUsername == null || post.retweetedByUsername!.isEmpty)) {
        // RT投稿: リツイーター情報が欠けている場合も保護 — 即時更新
        if (!existingUpdated) {
          existingUpdated = _engagementChanged(old, post);
        }
        existing[post.id] = old.copyWith(
          likedByAccountIds: mergedLikedBy,
          repostedByAccountIds: mergedRepostedBy,
          bskyLikeUris: mergedBskyLikeUris,
          bskyRepostUris: mergedBskyRepostUris,
          likeCount: post.likeCount,
          repostCount: post.repostCount,
          fetchedByAccountIds: mergedAccountIds,
        );
      } else if (old != null && old.isRetweet && !post.isRetweet) {
        // RT版が既にあるのに非RT版が来た場合、RTフラグ＋タイムスタンプを保持
        // (同じツイートがRT版と直接版の両方でフェッチされるケース)
        if (!existingUpdated) {
          existingUpdated = _engagementChanged(old, post);
        }
        existing[post.id] = post.copyWith(
          likedByAccountIds: mergedLikedBy,
          repostedByAccountIds: mergedRepostedBy,
          bskyLikeUris: mergedBskyLikeUris,
          bskyRepostUris: mergedBskyRepostUris,
          fetchedByAccountIds: mergedAccountIds,
          isRetweet: true,
          retweetedByUsername: old.retweetedByUsername,
          retweetedByHandle: old.retweetedByHandle,
          timestamp: old.timestamp, // RT時刻を保持
        );
      } else if (old != null) {
        // 既存投稿の更新（エンゲージメント等）— 即時反映
        if (!existingUpdated) {
          existingUpdated = _engagementChanged(old, post);
        }
        existing[post.id] = post.copyWith(
          likedByAccountIds: mergedLikedBy,
          repostedByAccountIds: mergedRepostedBy,
          bskyLikeUris: mergedBskyLikeUris,
          bskyRepostUris: mergedBskyRepostUris,
          fetchedByAccountIds: mergedAccountIds,
        );
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

    // 手動リフレッシュ・loadMore・初回（キャッシュ空）はドリップせず即時反映
    final shouldBypassDrip = _bypassDrip || state.posts.isEmpty;
    _bypassDrip = false;

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
        final topTimestamp = sorted.isNotEmpty ? sorted.first.timestamp : null;
        final drippable = <Post>[];

        for (final p in filtered) {
          if (topTimestamp != null && p.timestamp.isBefore(topTimestamp)) {
            if (_isAtTop) {
              // トップにいる場合: 古い投稿は直接挿入（下に入るのでスクロールに影響なし）
              sorted.add(p);
            }
            // スクロール中は古い投稿を捨てる（スクロール位置がずれる問題を防止）
          } else {
            drippable.add(p);
          }
        }

        // 直接挿入があった場合は再ソート
        if (_isAtTop && sorted.length > sortedIds.length) {
          sorted.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        }

        if (drippable.isNotEmpty) {
          _precachePostsImages(drippable);
          _pendingQueue.addAll(drippable);
          _pendingIds.addAll(drippable.map((p) => p.id));
          _pendingQueue.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        }

        newPendingCount = _pendingQueue.length;
      }
    }

    // 投稿リストに変化があったかチェック（件数・先頭ID・エンゲージメント更新）
    final oldPosts = state.posts;
    final postsChanged = existingUpdated ||
        sorted.length != oldPosts.length ||
        (sorted.isNotEmpty && oldPosts.isNotEmpty &&
            sorted.first.id != oldPosts.first.id);

    state = state.copyWith(
      posts: postsChanged ? sorted : null,
      isLoading: false,
      isFetching: false,
      clearError: true,
      pendingCount: newPendingCount,
    );


    // ドリップタイマー起動（_dripOne内でトップ判定するので、ここでは常に起動）
    if (_pendingQueue.isNotEmpty && _dripTimer == null) {
      _startDrip();
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

    // キューが上限を超えたら古い投稿を切り捨て
    if (_pendingQueue.length > _maxQueueSize) {
      _pendingQueue.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final removed = _pendingQueue.sublist(_maxQueueSize);
      for (final p in removed) {
        _pendingIds.remove(p.id);
      }
      _pendingQueue.removeRange(_maxQueueSize, _pendingQueue.length);
    }

    // 古い順にソート → 各ドリップが常にリスト先頭に挿入される
    _pendingQueue.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final schedulerIntervalMs =
        TimelineFetchScheduler.instance.interval.inMilliseconds;
    int intervalMs;
    if (_fastDripActive) {
      // 高速ドリップ: 動的速度（最速200ms = 5件/秒）
      if (_pendingQueue.length <= 30) {
        intervalMs =
            (schedulerIntervalMs / _pendingQueue.length).round().clamp(200, 3000);
      } else {
        intervalMs = 200;
      }
    } else {
      // 通常モード: 設定のドリップ間隔を使用
      final minInterval = _settingsReader().dripIntervalMs;
      intervalMs =
          (schedulerIntervalMs / _pendingQueue.length).round().clamp(minInterval, minInterval * 3);
    }

    _dripTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _dripOne();
    });
  }

  /// タイムライン画面が表示されているかどうか
  void setScreenVisible(bool visible) {
    _screenVisible = visible;
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
        if (_pendingQueue.isNotEmpty && _dripTimer == null) {
          _startDrip();
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
      deactivateFastDrip();
      return;
    }
    // 画面が見えていないならスキップ
    if (!_screenVisible) return;
    // オーバーレイ使用中はオーバーレイのスクロール位置のみで判定
    if (_overlayActive) {
      if (!_overlayAtTop) return;
    } else {
      if (!_isAtTop) return;
    }
    if (!mounted) {
      _dripTimer?.cancel();
      _dripTimer = null;
      return;
    }

    // ドリップ直前にソート（途中追加された投稿の順序を保証）
    if (_pendingQueue.length > 1) {
      _pendingQueue.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    // 重複をスキップして最初の有効な投稿を見つける
    final displayedIds = state.posts.map((p) => p.id).toSet();
    Post? post;
    while (_pendingQueue.isNotEmpty) {
      final candidate = _pendingQueue.removeAt(0);
      _pendingIds.remove(candidate.id);
      if (!displayedIds.contains(candidate.id)) {
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
    if (insertIndex > 0) {
      debugPrint('[Drip] Non-top insert: idx=$insertIndex '
          'post=${post.id}(${post.timestamp}) '
          'top=${posts.first.id}(${posts.first.timestamp}) '
          'fastDrip=$_fastDripActive queue=${_pendingQueue.length}');
    }
    posts.insert(insertIndex, post);

    state = state.copyWith(posts: posts, pendingCount: _pendingQueue.length);

    // キャッシュ更新（ドリップ中は間引き）
    _dripCacheSaveCounter++;
    if (_dripCacheSaveCounter >= _dripCacheSaveEveryN || _pendingQueue.isEmpty) {
      _dripCacheSaveCounter = 0;
      TimelineCacheService.instance.saveTimeline(posts);
    }

    // オーバーレイへ同期
    _syncToOverlay();
  }

  /// 高速ドリップを一時的に有効化（キュー消化で自動解除）
  void activateFastDrip() {
    _fastDripActive = true;
    state = state.copyWith(fastDripActive: true);
    if (_pendingQueue.isNotEmpty) {
      _startDrip();
    }
  }

  void deactivateFastDrip() {
    if (!_fastDripActive) return;
    _fastDripActive = false;
    if (mounted) {
      state = state.copyWith(fastDripActive: false);
    }
    // 通常ドリップに切り替え（古い順に戻す）
    if (_pendingQueue.isNotEmpty && _dripTimer != null) {
      _startDrip();
    }
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

    if (_pendingQueue.isNotEmpty && _isAtTop) {
      _startDrip();
    }

    return batch.length;
  }

  /// バナーモード: 溜まった投稿を一括でタイムラインに反映
  void flushPending() {
    if (_pendingQueue.isEmpty) return;
    _dripTimer?.cancel();
    _dripTimer = null;
    deactivateFastDrip();

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
    String? accountId,
    bool? liked,       // true = add to set, false = remove
    bool? reposted,    // true = add to set, false = remove
    int? likeCount,
    int? repostCount,
  }) {
    final idx = state.posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;
    final post = state.posts[idx];
    final posts = List<Post>.of(state.posts);

    var newLikedBy = Set<String>.of(post.likedByAccountIds);
    var newRepostedBy = Set<String>.of(post.repostedByAccountIds);

    if (accountId != null) {
      if (liked == true) newLikedBy.add(accountId);
      if (liked == false) newLikedBy.remove(accountId);
      if (reposted == true) newRepostedBy.add(accountId);
      if (reposted == false) newRepostedBy.remove(accountId);
    }

    posts[idx] = post.copyWith(
      likedByAccountIds: newLikedBy,
      repostedByAccountIds: newRepostedBy,
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
