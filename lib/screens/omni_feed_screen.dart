import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity_log.dart';
import '../models/post.dart';
import '../providers/activity_log_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/notification_badge_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/account_provider.dart';
import '../services/engagement_service.dart';
import '../services/app_update_service.dart';
import '../services/debug_log_service.dart';
import '../services/timeline_fetch_scheduler.dart';
import '../utils/app_snackbar.dart';
import '../widgets/feed_header_buttons.dart';
import '../widgets/home_rail.dart';
import '../utils/engagement_errors.dart';
import '../models/account.dart';
import '../widgets/account_picker_modal.dart';
import '../widgets/empty_state.dart';
import '../utils/smooth_scroll_physics.dart';
import '../widgets/post_card.dart';
import '../widgets/skeleton.dart';
import '../widgets/update_dialog.dart';
import 'accounts_screen.dart';
import 'compose_screen.dart';
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

  /// 左の列を出しているときのヘッダーの高さ。横向きは縦が狭いので低くする
  static const _railHeaderHeight = 44.0;

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
  bool? _lastHideAllRt;

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
        showAppSnackBar(
          context,
          '$handle のログインが切れました。再ログインしてください',
          type: SnackType.warning,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'アカウント',
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              _openAccountsScreen(context);
            },
          ),
        );
      };

      // ログは利用者が自分で有効にしたときだけ書かれる。整理したことは
      // 一言伝えるだけにして、容量の数字で驚かせない
      DebugLogService.instance.onLogSizeWarning = (sizeLabel) {
        if (!mounted) return;
        showAppSnackBar(context, 'ログが上限に達したので、古い分を整理しました');
      };
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingPostDetail();
      // メイン表示時はオーバーレイを閉じる（ドリップ状態の競合を防止）
      _closeOverlayIfActive();
      // フォアグラウンド復帰 → UI描画完了後にフェッチ再開（ANR防止）
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) ref.read(settingsProvider.notifier).resumeFetching();
      });
    } else if (state == AppLifecycleState.paused) {
      // バックグラウンド → オーバーレイも非表示ならフェッチ一時停止
      _pauseFetchingIfIdle();
    }
  }

  Future<void> _closeOverlayIfActive() async {
    try {
      final isActive = Platform.isAndroid ? await FlutterOverlayWindow.isActive() : false;
      if (isActive) {
        if (Platform.isAndroid) await FlutterOverlayWindow.closeOverlay();
      }
      ref.read(feedProvider.notifier).setOverlayActive(false);
    } catch (e) {
      debugPrint('[OmniFeed] _closeOverlayIfActive error: $e');
    }
  }

  Future<void> _pauseFetchingIfIdle() async {
    try {
      final isOverlayActive = Platform.isAndroid ? await FlutterOverlayWindow.isActive() : false;
      if (!isOverlayActive) {
        ref.read(settingsProvider.notifier).pauseFetching();
      }
    } catch (e) {
      debugPrint('[OmniFeed] _pauseFetchingIfIdle error: $e');
    }
  }

  Future<void> _checkPendingPostDetail() async {
    try {
      final json = Platform.isAndroid ? await FlutterOverlayWindow.getPendingPostDetail() : null;
      if (json == null || !mounted) return;
      final post = Post.fromCache(
          jsonDecode(json) as Map<String, dynamic>);
      ref.read(feedProvider.notifier).setScreenVisible(false);
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
      );
      if (mounted) ref.read(feedProvider.notifier).setScreenVisible(true);
    } catch (e) {
      debugPrint('[OmniFeed] _checkPendingPostDetail error: $e');
    }
  }

  bool _lastAtTop = true;
  bool _lastDripAtTop = true;

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final feed = ref.read(feedProvider);
      if (!feed.isLoadingMore) {
        ref.read(feedProvider.notifier).loadMore();
      }
    }

    // バナー表示用（50px の余裕）
    final atTop = _scrollController.offset <= 50;
    if (atTop != _lastAtTop) {
      _lastAtTop = atTop;
      setState(() {}); // バナー表示切替のため
    }

    // ドリップ制御用（5px — 少しでもスクロールしたらドリップ停止）
    final dripAtTop = _scrollController.offset <= 5;
    if (dripAtTop != _lastDripAtTop) {
      _lastDripAtTop = dripAtTop;
      ref.read(feedProvider.notifier).setScrollAtTop(dripAtTop);
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
      if (_lastAtTop) {
        // トップにいる場合: 全件フラッシュ（バナータップと同じ挙動）
        notifier.flushPending();
      } else {
        // スクロール途中: バッチ読み込み＋スクロール位置維持
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
      }
    } else {
      await notifier.refresh();
    }
  }

  Future<Account?> _resolveAccount(Post post, String actionLabel) async {
    return showAccountPickerModal(
      context,
      service: post.source,
      actionLabel: actionLabel,
      fetchedByAccountIds: post.fetchedByAccountIds,
      likedByAccountIds: post.likedByAccountIds,
      repostedByAccountIds: post.repostedByAccountIds,
    );
  }

  Future<void> _handleLike(Post post) async {
    HapticFeedback.lightImpact();
    final account = await _resolveAccount(post, 'いいね');
    if (account == null) return;

    final willUnlike = post.isLikedBy(account.id);
    final action = willUnlike ? ActivityAction.unlike : ActivityAction.like;

    ref.read(feedProvider.notifier).updatePostEngagement(
      post.id,
      accountId: account.id,
      liked: !willUnlike,
      likeCount: willUnlike ? post.likeCount - 1 : post.likeCount + 1,
    );

    final result = await EngagementService.instance.like(
      post: post, account: account, unlike: willUnlike,
    );

    ref.read(activityLogProvider.notifier).logAction(
      action: action,
      platform: post.source,
      accountHandle: account.handle,
      accountId: account.id,
      targetId: post.id,
      targetSummary: EngagementService.postSummary(post),
      success: result.success,
      statusCode: result.statusCode,
      responseSnippet: result.responseSnippet,
      errorMessage: result.errorMessage,
    );

    if (!result.success && mounted) {
      ref.read(feedProvider.notifier).updatePostEngagement(
        post.id, accountId: account.id, liked: willUnlike, likeCount: post.likeCount,
      );
      showEngagementError(context, 'いいね', result.statusCode);
    }
  }

  Future<void> _handleRepost(Post post) async {
    HapticFeedback.lightImpact();
    final account = await _resolveAccount(post, 'リポスト');
    if (account == null) return;

    final willUnrepost = post.isRepostedBy(account.id);
    final action = willUnrepost ? ActivityAction.unrepost : ActivityAction.repost;

    ref.read(feedProvider.notifier).updatePostEngagement(
      post.id,
      accountId: account.id,
      reposted: !willUnrepost,
      repostCount: willUnrepost ? post.repostCount - 1 : post.repostCount + 1,
    );

    final result = await EngagementService.instance.repost(
      post: post, account: account, unrepost: willUnrepost,
    );

    ref.read(activityLogProvider.notifier).logAction(
      action: action,
      platform: post.source,
      accountHandle: account.handle,
      accountId: account.id,
      targetId: post.id,
      targetSummary: EngagementService.postSummary(post),
      success: result.success,
      statusCode: result.statusCode,
      responseSnippet: result.responseSnippet,
      errorMessage: result.errorMessage,
    );

    if (!result.success && mounted) {
      ref.read(feedProvider.notifier).updatePostEngagement(
        post.id, accountId: account.id, reposted: willUnrepost, repostCount: post.repostCount,
      );
      showEngagementError(context, 'リポスト', result.statusCode);
    }
  }

  /// postsリストが変わった時だけフィルタリングを再計算
  List<Post> _getFilteredPosts(
    List<Post> posts,
    Set<String> enabledIds,
    Set<String> hideRtIds,
    bool hideAllRt,
    int totalAccounts,
  ) {
    // 同じpostsリスト + 同じフィルタ条件なら前回結果を返す
    if (identical(posts, _lastPosts) &&
        _cachedFilteredPosts != null &&
        _setsEqual(enabledIds, _lastEnabledIds) &&
        _setsEqual(hideRtIds, _lastHideRtIds) &&
        hideAllRt == _lastHideAllRt) {
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

    if (hideAllRt) {
      result = result.where((p) => !p.isRetweet).toList();
    } else if (hideRtIds.isNotEmpty) {
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
    _lastHideAllRt = hideAllRt;
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


  @override
  Widget build(BuildContext context) {
    // posts/pendingCount/fastDripActive が変わった時だけ rebuild
    final feed = ref.watch(feedProvider.select((f) => (
          posts: f.posts,
          pendingCount: f.pendingCount,
          fastDripActive: f.fastDripActive,
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

    // ホームが左の列を出しているときは、ヘッダーのボタンはそちらにある。
    // ヘッダーにはロゴと取得の進みだけを残す。先頭の投稿が画面の端に
    // 貼り付かないようにするためで、下へ送ると隠れ、上へ戻すと出る
    final railActive = HomeRailScope.isActive(context);

    Widget body = LayoutBuilder(
      builder: (context, constraints) {
        // 横に広い画面では、読みやすい幅に絞って画面の中央に置く。
        // 余白の上でもスクロールできるよう、リスト自体は幅いっぱいに取る
        final insets = railActive
            ? readableInsets(context, constraints.maxWidth)
            : EdgeInsets.zero;
        return CustomScrollView(
          cacheExtent: 800,
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: SmoothScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              floating: true,
              snap: false,
              toolbarHeight: railActive ? _railHeaderHeight : kToolbarHeight,
              leadingWidth: 0,
              leading: const SizedBox.shrink(),
              titleSpacing: 16,
              title: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ロゴ: 中央やや右に固定（Oの位置が画面中央）
                  Positioned.fill(
                    // 列のときは、本文の列の中央に合わせる
                    left: (insets.left - 16).clamp(0, double.infinity),
                    right: (insets.right - 16).clamp(0, double.infinity),
                    child: Align(
                      alignment: const Alignment(0.03, 0.0),
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
                          height: railActive ? 28 : 36,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  // 左右のボタン群（ロゴの上に配置）
                  Row(
                    children: [
                      if (!railActive) const FeedQuickButtons(),
                      const Spacer(),
                      if (railActive) const FeedIndicators(),
                      if (!railActive) const OverlayLaunchButton(),
                      if (!railActive)
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
            for (final sliver in _buildSliverBody(context,
                ref.read(feedProvider), settings, accounts, enabledAccountIds))
              insets == EdgeInsets.zero
                  ? sliver
                  : SliverPadding(padding: insets, sliver: sliver),
          ],
        );
      },
    );

    if (accounts.isNotEmpty) {
      body = RefreshIndicator(
        onRefresh: _handleRefresh,
        child: body,
      );
    }

    // バナー表示条件: (トップにいない かつ pending > 0) or (pending >= 100)
    final showBanner = feed.pendingCount > 0 &&
        (!_lastAtTop || feed.pendingCount >= 100);

    // 常にStackで包む（条件付きStack化はツリー構造が変わりスクロール位置がリセットされる）
    body = Stack(
      children: [
        body,
        if (showBanner)
          _buildNewPostsBanner(context, feed.pendingCount, feed.fastDripActive),
      ],
    );

    final hasAccounts = accounts.isNotEmpty;

    return Scaffold(
      // ヘッダーが無いぶん、ステータスバーの下から始める
      body: body,
      floatingActionButtonLocation: settings.fabPosition == FabPosition.left
          ? FloatingActionButtonLocation.startFloat
          : FloatingActionButtonLocation.endFloat,
      floatingActionButton: hasAccounts
          ? Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _showScrollToTop ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: _showScrollToTop
                ? Opacity(
                    opacity: 0.75,
                    child: FloatingActionButton.small(
                      heroTag: 'scrollTop',
                      onPressed: () {
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      child: const Icon(Icons.arrow_upward),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (_showScrollToTop) const SizedBox(height: 8),
          Opacity(
            opacity: 0.75,
            child: FloatingActionButton(
              heroTag: 'compose',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ComposeScreen()),
                );
              },
              child: const Icon(Icons.edit),
            ),
          ),
        ],
      )
          : null,
    );
  }

  Widget _buildNewPostsBanner(BuildContext context, int count, bool fastDripActive) {
    final canFastDrip = count >= 100;

    // 状態に応じたアイコン・テキスト・色を決定
    final IconData icon;
    final String label;
    final Color bgColor;
    final VoidCallback onTap;

    if (fastDripActive) {
      // 高速ドリップ中 → タップで高速ドリップ解除
      icon = Icons.bolt;
      label = '高速中 $count件';
      bgColor = Colors.orange.withValues(alpha: 0.88);
      onTap = () {
        ref.read(feedProvider.notifier).deactivateFastDrip();
      };
    } else if (canFastDrip) {
      // 100件以上 → タップで高速ドリップ開始＆ゆっくりトップへスクロール
      icon = Icons.bolt;
      label = '$count件の新しい投稿';
      bgColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.88);
      onTap = () {
        ref.read(feedProvider.notifier).activateFastDrip();
        // 現在のスクロール位置に応じた速度でトップへ（高速ドリップに合わせた体感速度）
        final offset = _scrollController.offset;
        final durationMs = (offset * 0.5).clamp(500, 3000).toInt();
        _scrollController.animateTo(
          0,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeInOut,
        );
      };
    } else {
      // 通常 → タップで全件フラッシュ＆トップへ
      icon = Icons.arrow_upward;
      label = '$count件の新しい投稿';
      bgColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.88);
      onTap = () {
        ref.read(feedProvider.notifier).flushPending();
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      };
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: bgColor,
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
                  Icon(icon, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    label,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🌊', style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  '静かな海です...',
                  style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                ),
                const SizedBox(height: 4),
                Text(
                  'アカウントを追加すると投稿が届きます',
                  style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    if (!settings.isFetchingActive && feed.posts.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(icon: Icons.pause_circle_outline, title: 'フェッチが停止中です'),
        ),
      ];
    }

    if (feed.isLoading && feed.posts.isEmpty) {
      // 投稿と同じ形の棒を並べて待つ。読み込み後に画面の形が変わらない
      final separator = settings.postCardStyle == PostCardStyle.separator;
      return [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => PostSkeleton(separator: separator, variant: i),
            childCount: 8,
          ),
        ),
      ];
    }

    // フィルタ適用（メモ化: postsリストが同一なら前回結果を再利用）
    final hideRtIds = settings.hideRetweetsAccountIds;
    final filteredPosts = _getFilteredPosts(feed.posts, enabledAccountIds, hideRtIds, settings.hideAllRetweets, accounts.length);

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
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(icon: Icons.hourglass_empty, title: '投稿が見つかりませんでした', subtitle: 'しばらくお待ちください...'),
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
              sensitiveMode: settings.sensitiveMode,
              compactEngagement: true,
              imagePreviewSize: settings.imagePreviewSize,
              hideUserInfo: settings.hideUserInfo,
              hideEngagement: settings.hideEngagement,
              useSeparatorStyle: settings.postCardStyle == PostCardStyle.separator,
              metaEmphasis: settings.postMetaEmphasis,
              onQuoteRepost: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(quotedPost: post),
                  ),
                );
              },
              onTap: () async {
                ref.read(feedProvider.notifier).setScreenVisible(false);
                await Navigator.of(context).push(
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
                if (mounted) ref.read(feedProvider.notifier).setScreenVisible(true);
              },
              onLike: () => _handleLike(post),
              onRepost: () => _handleRepost(post),
              onReply: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(inReplyToPost: post),
                  ),
                );
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

