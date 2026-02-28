import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import 'account_storage_service.dart';
import 'bluesky_api_service.dart';
import 'x_api_service.dart';

class TimelineFetchScheduler {
  TimelineFetchScheduler._();
  static final instance = TimelineFetchScheduler._();

  Timer? _timer;
  Duration _interval = const Duration(seconds: 60);
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// アカウント別のカーソル管理
  final Map<String, String?> _cursors = {};

  /// 新しい投稿が取得されたときのコールバック
  void Function(List<Post> posts)? onPostsFetched;

  /// TL 取得完了時のログコールバック (accountHandle, platform, success, postCount)
  void Function(String accountHandle, SnsService platform, bool success,
      int postCount, String? error)? onFetchLog;

  /// Bluesky トークンリフレッシュ通知コールバック
  void Function(String accountHandle, bool success)? onTokenRefresh;

  /// Bluesky トークンリフレッシュ完全失敗時（再ログイン必要）
  void Function(String accountId, String accountHandle)? onTokenExpired;

  void setInterval(Duration interval) {
    _interval = interval;
    if (_isRunning) {
      stop();
      start();
    }
  }

  void start() {
    _timer?.cancel();
    _isRunning = true;
    // 開始時に即座にフェッチ
    fetchAll();
    _timer = Timer.periodic(_interval, (_) => fetchAll());
    debugPrint('[Scheduler] Started with interval: ${_interval.inSeconds}s');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    debugPrint('[Scheduler] Stopped');
  }

  /// カーソルをリセット (Pull-to-refresh 時)
  void resetCursors() {
    _cursors.clear();
  }

  /// 全有効アカウントのタイムラインを並列取得 (最新)
  Future<void> fetchAll() async {
    final accounts = AccountStorageService.instance.accounts
        .where((a) => a.isEnabled)
        .toList();

    if (accounts.isEmpty) {
      debugPrint('[Scheduler] No enabled accounts, skipping fetch');
      return;
    }

    debugPrint('[Scheduler] Fetching timelines for ${accounts.length} accounts');

    final futures = accounts.map((account) => _fetchForAccount(account));
    final results = await Future.wait(futures, eagerError: false);

    final allPosts = <Post>[];
    for (final posts in results) {
      allPosts.addAll(posts);
    }

    if (allPosts.isNotEmpty) {
      onPostsFetched?.call(allPosts);
    }
  }

  /// 全有効アカウントの過去の投稿を並列取得 (カーソルベース)
  Future<void> fetchMore() async {
    final accounts = AccountStorageService.instance.accounts
        .where((a) => a.isEnabled)
        .toList();

    if (accounts.isEmpty) return;

    debugPrint('[Scheduler] Fetching more for ${accounts.length} accounts');

    final futures = accounts.map((account) => _fetchMoreForAccount(account));
    final results = await Future.wait(futures, eagerError: false);

    final allPosts = <Post>[];
    for (final posts in results) {
      allPosts.addAll(posts);
    }

    if (allPosts.isNotEmpty) {
      onPostsFetched?.call(allPosts);
    }
  }

  Future<List<Post>> _fetchForAccount(Account account) async {
    try {
      List<Post> posts;
      switch (account.service) {
        case SnsService.bluesky:
          posts = await _fetchBluesky(account);
        case SnsService.x:
          posts = await _fetchX(account);
      }
      onFetchLog?.call(
          account.handle, account.service, true, posts.length, null);
      return posts;
    } catch (e) {
      debugPrint('[Scheduler] Error fetching for ${account.handle}: $e');
      onFetchLog?.call(account.handle, account.service, false, 0, '$e');
      return [];
    }
  }

  Future<List<Post>> _fetchMoreForAccount(Account account) async {
    final cursor = _cursors[account.id];
    if (cursor == null) {
      debugPrint('[Scheduler] No cursor for ${account.handle}, skipping fetchMore');
      return [];
    }
    try {
      List<Post> posts;
      switch (account.service) {
        case SnsService.bluesky:
          posts = await _fetchBluesky(account, cursor: cursor);
        case SnsService.x:
          posts = await _fetchX(account, cursor: cursor);
      }
      debugPrint('[Scheduler] fetchMore for ${account.handle}: ${posts.length} posts');
      return posts;
    } catch (e) {
      debugPrint('[Scheduler] Error fetching more for ${account.handle}: $e');
      return [];
    }
  }

  Future<List<Post>> _fetchBluesky(Account account, {String? cursor}) async {
    final creds = account.blueskyCredentials;
    try {
      final result = await BlueskyApiService.instance.getTimelineWithRefresh(
        creds,
        accountId: account.id,
        cursor: cursor,
      );

      // トークンが更新された場合はストレージに保存
      if (result.updatedCreds != null) {
        final updated = account.copyWith(credentials: result.updatedCreds);
        await AccountStorageService.instance.updateAccount(updated);
        debugPrint('[Scheduler] Updated credentials for ${account.handle}');
        onTokenRefresh?.call(account.handle, true);
      }

      // カーソルを保存
      if (result.cursor != null) {
        _cursors[account.id] = result.cursor;
      }

      return result.posts;
    } on BlueskyAuthException {
      // refreshJwt も期限切れ → 再ログインが必要
      debugPrint('[Scheduler] Token fully expired for ${account.handle}');
      onTokenRefresh?.call(account.handle, false);
      onTokenExpired?.call(account.id, account.handle);
      rethrow;
    }
  }

  Future<List<Post>> _fetchX(Account account, {String? cursor}) async {
    final creds = account.xCredentials;
    final result = await XApiService.instance.getTimeline(
      creds,
      accountId: account.id,
      cursor: cursor,
    );

    // カーソルを保存
    if (result.cursor != null) {
      _cursors[account.id] = result.cursor;
    }

    return result.posts;
  }
}
