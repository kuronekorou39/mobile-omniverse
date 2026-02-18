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

  /// 新しい投稿が取得されたときのコールバック
  void Function(List<Post> posts)? onPostsFetched;

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

  /// 全有効アカウントのタイムラインを並列取得
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

  Future<List<Post>> _fetchForAccount(Account account) async {
    try {
      switch (account.service) {
        case SnsService.bluesky:
          return await _fetchBluesky(account);
        case SnsService.x:
          return await _fetchX(account);
      }
    } catch (e) {
      debugPrint('[Scheduler] Error fetching for ${account.handle}: $e');
      return [];
    }
  }

  Future<List<Post>> _fetchBluesky(Account account) async {
    final creds = account.blueskyCredentials;
    final result = await BlueskyApiService.instance.getTimelineWithRefresh(
      creds,
      accountId: account.id,
    );

    // トークンが更新された場合はストレージに保存
    if (result.updatedCreds != null) {
      final updated = account.copyWith(credentials: result.updatedCreds);
      await AccountStorageService.instance.updateAccount(updated);
      debugPrint('[Scheduler] Updated credentials for ${account.handle}');
    }

    return result.posts;
  }

  Future<List<Post>> _fetchX(Account account) async {
    final creds = account.xCredentials;
    return await XApiService.instance.getTimeline(
      creds,
      accountId: account.id,
    );
  }
}
