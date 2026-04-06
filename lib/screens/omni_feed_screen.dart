import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/notification_badge_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/account_provider.dart';
import '../services/account_storage_service.dart';
import '../services/x_api_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/app_update_service.dart';
import '../services/debug_log_service.dart';
import '../services/timeline_fetch_scheduler.dart';
import '../models/account.dart';
import '../widgets/account_picker_modal.dart';
import '../utils/smooth_scroll_physics.dart';
import '../widgets/post_card.dart';
import '../widgets/update_dialog.dart';
import 'accounts_screen.dart';
import 'compose_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'post_detail_screen.dart';

class OmniFeedScreen extends ConsumerStatefulWidget {
  const OmniFeedScreen({super.key, this.onRegisterTimelineTap});

  /// タイムラインタブ再タップ時のコールバック登録
  final void Function(VoidCallback)? onRegisterTimelineTap;

  @override
  ConsumerState<OmniFeedScreen> createState() => _OmniFeedScreenState();
}

class _OmniFeedScreenState extends ConsumerState<OmniFeedScreen>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();

  /// スクロールトップボタン表示
  bool _showScrollToTop = false;

  /// アニメーション対象の投稿ID
  final Set<String> _animatingPostIds = {};

  /// 前回の投稿IDリスト（新規投稿検出用）
  Set<String> _prevPostIds = {};

  /// フィルタ結果のメモ化（postsリストが変わった時だけ再計算）
  List<Post>? _cachedFilteredPosts;
  List<Post>? _lastPosts;
  Set<String>? _lastEnabledIds;
  Set<String>? _lastHideRtIds;

  /// カウントダウン用
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  bool _wasFetching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);

    // タイムラインタブ再タップ → トップにスクロール
    widget.onRegisterTimelineTap?.call(() {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
    _startCountdownTimer();
    // スケジューラのサイクル完了時に通知バッジをチェック
    TimelineFetchScheduler.instance.onCycleComplete = () {
      ref.read(notificationBadgeProvider.notifier).onSchedulerCycle();
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingPostDetail();
      _checkForUpdate();
      // トークン期限切れ通知を設定
      ref.read(feedProvider.notifier).onTokenExpired = (accountId, handle) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('$handle のトークンが期限切れです。再ログインしてください'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'アカウント',
              onPressed: () {
                messenger.hideCurrentSnackBar();
                _openAccountsScreen(context);
              },
            ),
          ),
        );
      };

      // ログサイズ警告を設定
      DebugLogService.instance.onLogSizeWarning = (sizeLabel) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('デバッグログが上限に達したため自動整理しました（現在 $sizeLabel）'),
            duration: const Duration(seconds: 3),
          ),
        );
      };
    });
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final isFetching = ref.read(feedProvider).isFetching;

      // フェッチ完了時にカウントダウンをリセット
      if (_wasFetching && !isFetching) {
        _remainingSeconds = ref.read(settingsProvider).fetchIntervalSeconds;
      }
      _wasFetching = isFetching;

      if (!isFetching && _remainingSeconds > 0) {
        _remainingSeconds--;
      }
      // タイマー表示が有効な場合のみ再描画（スクロールへの影響を最小化）
      if (ref.read(settingsProvider).showFetchTimer) {
        setState(() {});
      }
    });
  }

  Future<void> _checkForUpdate() async {
    final info = await AppUpdateService.instance.checkForUpdate();
    if (info != null && mounted) {
      showUpdateDialog(context, info);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingPostDetail();
      // フォアグラウンド復帰 → フェッチ再開
      ref.read(settingsProvider.notifier).resumeFetching();
      // メイン表示時はオーバーレイを閉じる（ドリップ状態の競合を防止）
      _closeOverlayIfActive();
    } else if (state == AppLifecycleState.paused) {
      // バックグラウンド → オーバーレイも非表示ならフェッチ一時停止
      _pauseFetchingIfIdle();
    }
  }

  Future<void> _closeOverlayIfActive() async {
    try {
      final isActive = await FlutterOverlayWindow.isActive();
      if (isActive) {
        await FlutterOverlayWindow.closeOverlay();
      }
      ref.read(feedProvider.notifier).setOverlayActive(false);
    } catch (_) {}
  }

  Future<void> _pauseFetchingIfIdle() async {
    try {
      final isOverlayActive = await FlutterOverlayWindow.isActive();
      if (!isOverlayActive) {
        ref.read(settingsProvider.notifier).pauseFetching();
      }
    } catch (_) {}
  }

  Future<void> _checkPendingPostDetail() async {
    try {
      final json = await FlutterOverlayWindow.getPendingPostDetail();
      if (json == null || !mounted) return;
      final post = Post.fromCache(
          jsonDecode(json) as Map<String, dynamic>);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
      );
    } catch (_) {}
  }

  bool _lastAtTop = true;

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final feed = ref.read(feedProvider);
      if (!feed.isLoadingMore) {
        ref.read(feedProvider.notifier).loadMore();
      }
    }

    // スクロール位置をフィードに通知（変化時のみ）
    final atTop = _scrollController.offset <= 50;
    if (atTop != _lastAtTop) {
      _lastAtTop = atTop;
      ref.read(feedProvider.notifier).setScrollAtTop(atTop);
    }

    // スクロールトップボタンの表示制御（変化時のみsetState）
    final shouldShow = _scrollController.offset > 300;
    if (shouldShow != _showScrollToTop) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  Future<void> _handleRefresh() async {
    final notifier = ref.read(feedProvider.notifier);
    if (notifier.hasPending) {
      // ペンディングがある場合: バッチ読み込み＋スクロール位置維持
      final oldOffset = _scrollController.offset;
      final oldMaxExtent = _scrollController.position.maxScrollExtent;

      notifier.flushPendingBatch(20);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final newMaxExtent = _scrollController.position.maxScrollExtent;
        final delta = newMaxExtent - oldMaxExtent;
        if (delta > 0) {
          _scrollController.jumpTo(oldOffset + delta);
        }
      });
    } else {
      await notifier.refresh();
    }
  }

  Future<Account?> _resolveAccount(Post post, String actionLabel) async {
    return showAccountPickerModal(
      context,
      service: post.source,
      actionLabel: actionLabel,
      fetchedByAccountId: post.accountId,
    );
  }

  Future<void> _handleLike(Post post) async {
    final account = await _resolveAccount(post, 'いいね');
    if (account == null) return;

    final postSummary = post.body.length > 40
        ? '${post.body.substring(0, 40)}...'
        : post.body;

    try {
      bool success = false;
      int? statusCode;
      String? responseSnippet;

      if (post.source == SnsService.x) {
        final creds = account.xCredentials;
        final tweetId = post.id.replaceFirst('x_', '');
        final result = await XApiService.instance.likeTweetWithDetail(creds, tweetId);
        success = result.success;
        statusCode = result.statusCode;
        responseSnippet = result.bodySnippet;
      } else if (post.source == SnsService.bluesky) {
        final creds = account.blueskyCredentials;
        final postUri = post.uri;
        final postCid = post.cid;
        if (postUri != null && postCid != null && postCid.isNotEmpty) {
          final result = await BlueskyApiService.instance.likePost(
              creds, postUri, postCid);
          success = result != null;
        }
      }

      ref.read(activityLogProvider.notifier).logAction(
            action: ActivityAction.like,
            platform: post.source,
            accountHandle: account.handle,
            accountId: account.id,
            targetId: post.id,
            targetSummary: postSummary,
            success: success,
            statusCode: statusCode,
            responseSnippet: responseSnippet,
          );
    } catch (e) {
      ref.read(activityLogProvider.notifier).logAction(
            action: ActivityAction.like,
            platform: post.source,
            accountHandle: account.handle,
            accountId: account.id,
            targetId: post.id,
            targetSummary: postSummary,
            success: false,
            errorMessage: e.toString(),
          );
    }
  }

  Future<void> _handleRepost(Post post) async {
    final account = await _resolveAccount(post, 'リポスト');
    if (account == null) return;

    final postSummary = post.body.length > 40
        ? '${post.body.substring(0, 40)}...'
        : post.body;

    try {
      bool success = false;
      int? statusCode;
      String? responseSnippet;

      if (post.source == SnsService.x) {
        final creds = account.xCredentials;
        final tweetId = post.id.replaceFirst('x_', '');
        final result = await XApiService.instance.retweetWithDetail(creds, tweetId);
        success = result.success;
        statusCode = result.statusCode;
        responseSnippet = result.bodySnippet;
      } else if (post.source == SnsService.bluesky) {
        final creds = account.blueskyCredentials;
        final postUri = post.uri;
        final postCid = post.cid;
        if (postUri != null && postCid != null && postCid.isNotEmpty) {
          final result = await BlueskyApiService.instance.repost(
              creds, postUri, postCid);
          success = result != null;
        }
      }

      ref.read(activityLogProvider.notifier).logAction(
            action: ActivityAction.repost,
            platform: post.source,
            accountHandle: account.handle,
            accountId: account.id,
            targetId: post.id,
            targetSummary: postSummary,
            success: success,
            statusCode: statusCode,
            responseSnippet: responseSnippet,
          );
    } catch (e) {
      ref.read(activityLogProvider.notifier).logAction(
            action: ActivityAction.repost,
            platform: post.source,
            accountHandle: account.handle,
            accountId: account.id,
            targetId: post.id,
            targetSummary: postSummary,
            success: false,
            errorMessage: e.toString(),
          );
    }
  }

  /// postsリストが変わった時だけフィルタリングを再計算
  List<Post> _getFilteredPosts(
    List<Post> posts,
    Set<String> enabledIds,
    Set<String> hideRtIds,
    int totalAccounts,
  ) {
    // 同じpostsリスト + 同じフィルタ条件なら前回結果を返す
    if (identical(posts, _lastPosts) &&
        _cachedFilteredPosts != null &&
        _setsEqual(enabledIds, _lastEnabledIds) &&
        _setsEqual(hideRtIds, _lastHideRtIds)) {
      return _cachedFilteredPosts!;
    }

    var result = posts;

    if (enabledIds.length < totalAccounts) {
      result = result
          .where((p) =>
              p.fetchedByAccountIds.isEmpty ||
              p.fetchedByAccountIds.any((id) => enabledIds.contains(id)))
          .toList();
    }

    if (hideRtIds.isNotEmpty) {
      result = result
          .where((p) =>
              !p.isRetweet ||
              p.fetchedByAccountIds.isEmpty ||
              p.fetchedByAccountIds.any((id) => !hideRtIds.contains(id)))
          .toList();
    }

    _lastPosts = posts;
    _lastEnabledIds = enabledIds;
    _lastHideRtIds = hideRtIds;
    _cachedFilteredPosts = result;
    return result;
  }

  static bool _setsEqual(Set<String>? a, Set<String>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  void _openAccountsScreen(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (context, anim1, anim2) => const AccountsScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
    ));
  }

  /// AppBarカスタムボタンの定義
  static const appBarButtonDefs = {
    'sensitive': ('センシティブ表示', Icons.visibility_off, Icons.visibility),
    'userInfo': ('ユーザー情報', Icons.person_off_outlined, Icons.person_outline),
  };

  List<Widget> _buildAppBarLeftButtons(SettingsState settings) {
    final buttons = <Widget>[];
    final notifier = ref.read(settingsProvider.notifier);

    // フェッチタイマー（アカウントがある場合のみ）
    final hasAccounts = ref.read(accountProvider).isNotEmpty;
    if (hasAccounts && settings.isFetchingActive && settings.showFetchTimer) {
      buttons.add(_buildFetchIndicator(context, settings));
    }

    if (settings.appBarButtons.contains('sensitive')) {
      final isFiltering = !settings.showSensitiveContent;
      buttons.add(IconButton(
        icon: Icon(
          isFiltering ? Icons.blur_on : Icons.blur_off,
          size: 20,
        ),
        tooltip: isFiltering ? 'モザイク: ON' : 'モザイク: OFF',
        onPressed: () => notifier.setShowSensitiveContent(!settings.showSensitiveContent),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ));
    }

    if (settings.appBarButtons.contains('userInfo')) {
      final isHiding = settings.hideUserInfo;
      buttons.add(IconButton(
        icon: Icon(
          isHiding ? Icons.face_retouching_off : Icons.face_retouching_natural,
          size: 20,
        ),
        tooltip: isHiding ? '匿名モード: ON' : '匿名モード: OFF',
        onPressed: () => notifier.setHideUserInfo(!isHiding),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ));
    }

    return buttons;
  }

  void _openSettingsScreen(BuildContext context) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (context, anim1, anim2) => const SettingsScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
    ));
  }

  Future<void> _launchOverlay(FeedState feed) async {
    final messenger = ScaffoldMessenger.of(context);

    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('権限未許可 → 設定画面を開きます')),
      );
      await FlutterOverlayWindow.requestPermission();
      return;
    }

    final isActive = await FlutterOverlayWindow.isActive();
    if (isActive) {
      await FlutterOverlayWindow.closeOverlay();
      ref.read(feedProvider.notifier).setOverlayActive(false);
      return;
    }

    try {
      await FlutterOverlayWindow.showOverlay(
        height: 250,
        width: 180,
        enableDrag: false,
        overlayTitle: 'OmniVerse',
        flag: OverlayFlag.defaultFlag,
        positionGravity: PositionGravity.none,
      );

      final posts = feed.posts.take(100).map((p) => p.toJson()).toList();
      final settings = ref.read(settingsProvider);
      await FlutterOverlayWindow.shareData(jsonEncode({
        'posts': posts,
        'fetch': {
          'remaining': 0,
          'total': settings.fetchIntervalSeconds,
          'isFetching': ref.read(feedProvider).isFetching,
        },
        'showFetchTimer': settings.showFetchTimer,
      }));

      ref.read(feedProvider.notifier).setOverlayActive(true);

      // ホーム画面に戻る（Activityを破棄せずバックグラウンドへ）
      if (mounted) {
        await FlutterOverlayWindow.moveToBackground();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('オーバーレイエラー: $e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    // posts/pendingCount が変わった時だけ rebuild（isFetchingの変更では rebuild しない）
    final feed = ref.watch(feedProvider.select((f) => (
          posts: f.posts,
          pendingCount: f.pendingCount,
          isLoading: f.isLoading,
          isLoadingMore: f.isLoadingMore,
          error: f.error,
        )));
    final settings = ref.watch(settingsProvider);
    final accounts = ref.watch(accountProvider);

    // 有効アカウントIDでフィルタ用
    final enabledAccountIds = accounts
        .where((a) => a.isEnabled)
        .map((a) => a.id)
        .toSet();

    // 新規投稿をアニメーション対象として検出（少数のドリップのみ）
    final currentPostIds = feed.posts.map((p) => p.id).toSet();
    if (_prevPostIds.isNotEmpty) {
      final newIds = currentPostIds.difference(_prevPostIds);
      if (newIds.isNotEmpty && newIds.length <= 5) { // 少数のドリップのみアニメーション
        _animatingPostIds.addAll(newIds);
      }
    }
    _prevPostIds = currentPostIds;

    Widget body = CustomScrollView(
      cacheExtent: 800,
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: SmoothScrollPhysics(),
      ),
      slivers: [
        SliverAppBar(
          floating: true,
          snap: false,
          leadingWidth: 0,
          leading: const SizedBox.shrink(),
          titleSpacing: 16,
          title: Stack(
            clipBehavior: Clip.none,
            children: [
              // ロゴ: 中央やや右に固定（Oの位置が画面中央）
              Positioned.fill(
                child: Align(
                  alignment: const Alignment(0.05, 0.0),
                  child: GestureDetector(
                    onTap: () {
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: Image.asset(
                      'assets/logo.png',
                      height: 36,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              // 左右のボタン群（ロゴの上に配置）
              Row(
                children: [
                  ..._buildAppBarLeftButtons(settings),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.picture_in_picture_alt, size: 20),
                    tooltip: 'オーバーレイ',
                    onPressed: () => _launchOverlay(ref.read(feedProvider)),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    tooltip: '設定',
                    onPressed: () => _openSettingsScreen(context),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
        ..._buildSliverBody(
            context, ref.read(feedProvider), settings, accounts, enabledAccountIds),
      ],
    );

    if (accounts.isNotEmpty) {
      body = RefreshIndicator(
        onRefresh: _handleRefresh,
        child: body,
      );
    }

    final hasAccounts = accounts.isNotEmpty;

    return Scaffold(
      body: body,
      floatingActionButton: hasAccounts
          ? Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _showScrollToTop ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: _showScrollToTop
                ? FloatingActionButton.small(
                    heroTag: 'scrollTop',
                    onPressed: () {
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: const Icon(Icons.arrow_upward),
                  )
                : const SizedBox.shrink(),
          ),
          if (_showScrollToTop) const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'compose',
            onPressed: () async {
              final posted = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const ComposeScreen()),
              );
              if (posted == true) {
                ref.read(feedProvider.notifier).refresh();
              }
            },
            child: const Icon(Icons.edit),
          ),
        ],
      )
          : null,
    );
  }

  Widget _buildFetchIndicator(
      BuildContext context, SettingsState settings) {
    final total = settings.fetchIntervalSeconds;
    final remaining = _remainingSeconds.clamp(0, total);
    final progress = total > 0 ? remaining / total : 0.0;
    final pendingCount = ref.read(feedProvider).pendingCount;
    final showPending = pendingCount > 0;

    // IconButtonと同じconstraints/paddingで間隔を統一
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: remaining == 0
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : CircularProgressIndicator(
                        value: progress.toDouble(),
                        strokeWidth: 2,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
              ),
              if (showPending)
                Center(
                  child: Text(
                    '+$pendingCount',
                    style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewPostsBanner(BuildContext context, int count) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              ref.read(feedProvider.notifier).flushPending();
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_upward,
                      size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '$count件の新しい投稿',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSliverBody(
    BuildContext context,
    FeedState feed,
    SettingsState settings,
    List<Account> accounts,
    Set<String> enabledAccountIds,
  ) {
    if (accounts.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'アカウントタブからアカウントを追加してください',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ),
        ),
      ];
    }

    if (!settings.isFetchingActive && feed.posts.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'フェッチが停止中です',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ),
        ),
      ];
    }

    if (feed.isLoading && feed.posts.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    // フィルタ適用（メモ化: postsリストが同一なら前回結果を再利用）
    final hideRtIds = settings.hideRetweetsAccountIds;
    final filteredPosts = _getFilteredPosts(feed.posts, enabledAccountIds, hideRtIds, accounts.length);

    final slivers = <Widget>[];

    // Error banner
    if (feed.error != null) {
      slivers.add(SliverToBoxAdapter(
        child: MaterialBanner(
          content: Text(
            feed.error!,
            style: const TextStyle(fontSize: 13),
          ),
          leading: const Icon(Icons.error_outline, color: Colors.red),
          actions: [
            TextButton(
              onPressed: () => ref.read(feedProvider.notifier).refresh(),
              child: const Text('リトライ'),
            ),
            TextButton(
              onPressed: () => ref.read(feedProvider.notifier).clearError(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ));
    }

    // Post list
    if (filteredPosts.isEmpty) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              '投稿が見つかりませんでした。\nしばらくお待ちください...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    } else {
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= filteredPosts.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final post = filteredPosts[index];
            final postCard = PostCard(
              key: ValueKey(post.id),
              post: post,
              hideSensitive: !settings.showSensitiveContent,
              compactEngagement: true,
              imageMaxHeight: settings.imagePreviewSize.singleImageMaxHeight,
              imageGridHeight: settings.imagePreviewSize.gridImageHeight,
              videoHeight: settings.imagePreviewSize.videoHeight,
              hideUserInfo: settings.hideUserInfo,
              onQuoteRepost: () async {
                final posted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(quotedPost: post),
                  ),
                );
                if (posted == true) {
                  ref.read(feedProvider.notifier).refresh();
                }
              },
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, anim1, anim2) =>
                        PostDetailScreen(post: post),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                      return SlideTransition(
                        position: Tween(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        )),
                        child: child,
                      );
                    },
                  ),
                );
              },
              onLike: () => _handleLike(post),
              onRepost: () => _handleRepost(post),
              onReply: () async {
                final posted = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(inReplyToPost: post),
                  ),
                );
                if (posted == true) {
                  ref.read(feedProvider.notifier).refresh();
                }
              },
            );

            if (_animatingPostIds.contains(post.id)) {
              return RepaintBoundary(
                child: _AnimatedPostCard(
                  key: ValueKey('anim_${post.id}'),
                  onAnimationComplete: () {
                    _animatingPostIds.remove(post.id);
                  },
                  child: postCard,
                ),
              );
            }
            return RepaintBoundary(child: postCard);
          },
          childCount:
              filteredPosts.length + (feed.isLoadingMore ? 1 : 0),
        ),
      ));
    }

    return slivers;
  }
}

class _AnimatedPostCard extends StatefulWidget {
  const _AnimatedPostCard({
    super.key,
    required this.child,
    required this.onAnimationComplete,
  });

  final Widget child;
  final VoidCallback onAnimationComplete;

  @override
  State<_AnimatedPostCard> createState() => _AnimatedPostCardState();
}

class _AnimatedPostCardState extends State<_AnimatedPostCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sizeAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _sizeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _sizeAnimation,
      axisAlignment: -1.0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: widget.child,
      ),
    );
  }
}
