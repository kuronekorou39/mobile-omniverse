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
import '../providers/settings_provider.dart';
import '../providers/account_provider.dart';
import '../services/account_storage_service.dart';
import '../services/x_api_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/app_update_service.dart';
import '../models/account.dart';
import '../widgets/account_picker_modal.dart';
import '../widgets/post_card.dart';
import '../widgets/update_dialog.dart';
import 'accounts_screen.dart';
import 'activity_log_screen.dart';
import 'bookmarks_screen.dart';
import 'compose_screen.dart';
import 'settings_screen.dart';
import 'post_detail_screen.dart';

class OmniFeedScreen extends ConsumerStatefulWidget {
  const OmniFeedScreen({super.key});

  @override
  ConsumerState<OmniFeedScreen> createState() => _OmniFeedScreenState();
}

class _OmniFeedScreenState extends ConsumerState<OmniFeedScreen> {
  final _scrollController = ScrollController();

  /// スクロールトップボタン表示
  bool _showScrollToTop = false;

  /// アニメーション対象の投稿ID
  final Set<String> _animatingPostIds = {};

  /// 前回の投稿IDリスト（新規投稿検出用）
  Set<String> _prevPostIds = {};

  /// カウントダウン用
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  bool _wasFetching = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _startCountdownTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
      // トークン期限切れ通知を設定
      ref.read(feedProvider.notifier).onTokenExpired = (accountId, handle) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$handle のトークンが期限切れです。再ログインしてください'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'アカウント',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountsScreen()),
                );
              },
            ),
          ),
        );
      };
    });
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final feed = ref.read(feedProvider);

      // フェッチ完了時にカウントダウンをリセット
      if (_wasFetching && !feed.isFetching) {
        final interval = ref.read(settingsProvider).fetchIntervalSeconds;
        setState(() => _remainingSeconds = interval);
      }
      _wasFetching = feed.isFetching;

      if (!feed.isFetching && _remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
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
    _countdownTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final feed = ref.read(feedProvider);
      if (!feed.isLoadingMore) {
        ref.read(feedProvider.notifier).loadMore();
      }
    }

    // スクロール位置をフィードに通知
    final atTop = _scrollController.offset <= 50;
    ref.read(feedProvider.notifier).setScrollAtTop(atTop);

    // スクロールトップボタンの表示制御
    final shouldShow = _scrollController.offset > 300;
    if (shouldShow != _showScrollToTop) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  Future<Account?> _resolveAccount(Post post, String actionLabel) async {
    final settings = ref.read(settingsProvider);
    if (settings.showAccountPickerOnEngagement) {
      final picked = await showAccountPickerModal(
        context,
        service: post.source,
        actionLabel: actionLabel,
      );
      return picked;
    }
    return _getAccountForPost(post);
  }

  Future<void> _handleLike(Post post) async {
    final account = await _resolveAccount(post, 'いいね');
    if (account == null) return;

    final wasLiked = post.isLiked;
    final action = wasLiked ? ActivityAction.unlike : ActivityAction.like;
    final postSummary = post.body.length > 40
        ? '${post.body.substring(0, 40)}...'
        : post.body;

    // Optimistic update
    ref.read(feedProvider.notifier).updatePostEngagement(
          post.id,
          isLiked: !wasLiked,
          likeCount: wasLiked ? post.likeCount - 1 : post.likeCount + 1,
        );

    try {
      bool success = false;
      int? statusCode;
      String? responseSnippet;

      if (post.source == SnsService.x) {
        final creds = account.xCredentials;
        final tweetId = post.id.replaceFirst('x_', '');
        final result = wasLiked
            ? await XApiService.instance.unlikeTweetWithDetail(creds, tweetId)
            : await XApiService.instance.likeTweetWithDetail(creds, tweetId);
        success = result.success;
        statusCode = result.statusCode;
        responseSnippet = result.bodySnippet;
      } else if (post.source == SnsService.bluesky) {
        final creds = account.blueskyCredentials;
        if (wasLiked) {
          success = true;
        } else {
          final postUri = post.uri;
          final postCid = post.cid;
          if (postUri != null && postCid != null && postCid.isNotEmpty) {
            final result = await BlueskyApiService.instance.likePost(
                creds, postUri, postCid);
            success = result != null;
          }
        }
      }

      ref.read(activityLogProvider.notifier).logAction(
            action: action,
            platform: post.source,
            accountHandle: account.handle,
            accountId: account.id,
            targetId: post.id,
            targetSummary: postSummary,
            success: success,
            statusCode: statusCode,
            responseSnippet: responseSnippet,
          );

      if (!success) {
        ref.read(feedProvider.notifier).updatePostEngagement(
              post.id,
              isLiked: wasLiked,
              likeCount: post.likeCount,
            );
      }
    } catch (e) {
      ref.read(activityLogProvider.notifier).logAction(
            action: action,
            platform: post.source,
            accountHandle: account.handle,
            accountId: account.id,
            targetId: post.id,
            targetSummary: postSummary,
            success: false,
            errorMessage: e.toString(),
          );
      ref.read(feedProvider.notifier).updatePostEngagement(
            post.id,
            isLiked: wasLiked,
            likeCount: post.likeCount,
          );
    }
  }

  Future<void> _handleRepost(Post post) async {
    final account = await _resolveAccount(post, 'リポスト');
    if (account == null) return;

    final wasReposted = post.isReposted;
    final action =
        wasReposted ? ActivityAction.unrepost : ActivityAction.repost;
    final postSummary = post.body.length > 40
        ? '${post.body.substring(0, 40)}...'
        : post.body;

    ref.read(feedProvider.notifier).updatePostEngagement(
          post.id,
          isReposted: !wasReposted,
          repostCount:
              wasReposted ? post.repostCount - 1 : post.repostCount + 1,
        );

    try {
      bool success = false;
      int? statusCode;
      String? responseSnippet;

      if (post.source == SnsService.x) {
        final creds = account.xCredentials;
        final tweetId = post.id.replaceFirst('x_', '');
        final result = wasReposted
            ? await XApiService.instance.unretweetWithDetail(creds, tweetId)
            : await XApiService.instance.retweetWithDetail(creds, tweetId);
        success = result.success;
        statusCode = result.statusCode;
        responseSnippet = result.bodySnippet;
      } else if (post.source == SnsService.bluesky) {
        final creds = account.blueskyCredentials;
        if (wasReposted) {
          success = true;
        } else {
          final postUri = post.uri;
          final postCid = post.cid;
          if (postUri != null && postCid != null && postCid.isNotEmpty) {
            final result = await BlueskyApiService.instance.repost(
                creds, postUri, postCid);
            success = result != null;
          }
        }
      }

      ref.read(activityLogProvider.notifier).logAction(
            action: action,
            platform: post.source,
            accountHandle: account.handle,
            accountId: account.id,
            targetId: post.id,
            targetSummary: postSummary,
            success: success,
            statusCode: statusCode,
            responseSnippet: responseSnippet,
          );

      if (!success) {
        ref.read(feedProvider.notifier).updatePostEngagement(
              post.id,
              isReposted: wasReposted,
              repostCount: post.repostCount,
            );
      }
    } catch (e) {
      ref.read(activityLogProvider.notifier).logAction(
            action: action,
            platform: post.source,
            accountHandle: account.handle,
            accountId: account.id,
            targetId: post.id,
            targetSummary: postSummary,
            success: false,
            errorMessage: e.toString(),
          );
      ref.read(feedProvider.notifier).updatePostEngagement(
            post.id,
            isReposted: wasReposted,
            repostCount: post.repostCount,
          );
    }
  }

  Future<void> _launchOverlay(FeedState feed) async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      final result = await FlutterOverlayWindow.requestPermission();
      if (result != true) return;
    }

    final isActive = await FlutterOverlayWindow.isActive();
    if (isActive) {
      await FlutterOverlayWindow.closeOverlay();
      return;
    }

    await FlutterOverlayWindow.showOverlay(
      height: 450,
      width: WindowSize.matchParent,
      enableDrag: true,
      overlayTitle: 'OmniVerse',
      flag: OverlayFlag.defaultFlag,
      positionGravity: PositionGravity.auto,
    );

    // Send current posts to overlay
    final posts = feed.posts.take(20).map((p) => p.toJson()).toList();
    await FlutterOverlayWindow.shareData(jsonEncode(posts));
  }

  Account? _getAccountForPost(Post post) {
    if (post.accountId == null) return null;
    return AccountStorageService.instance.getAccount(post.accountId!);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final settings = ref.watch(settingsProvider);
    final accounts = ref.watch(accountProvider);

    // 有効アカウントIDでフィルタ用
    final enabledAccountIds = accounts
        .where((a) => a.isEnabled)
        .map((a) => a.id)
        .toSet();

    // 新規投稿をアニメーション対象として検出
    final currentPostIds = feed.posts.map((p) => p.id).toSet();
    if (_prevPostIds.isNotEmpty) {
      final newIds = currentPostIds.difference(_prevPostIds);
      if (newIds.isNotEmpty) {
        _animatingPostIds.addAll(newIds);
      }
    }
    _prevPostIds = currentPostIds;

    Widget body = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          floating: true,
          snap: true,
          title: const Text(
            'OmniVerse',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'アカウント',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountsScreen()),
              );
            },
          ),
          actions: [
            if (settings.isFetchingActive)
              _buildFetchIndicator(context, feed, settings),
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt),
              tooltip: 'オーバーレイ',
              onPressed: () => _launchOverlay(feed),
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_outline),
              tooltip: 'ブックマーク',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BookmarksScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'ログ',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '設定',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
        ..._buildSliverBody(
            context, feed, settings, accounts, enabledAccountIds),
      ],
    );

    if (accounts.isNotEmpty) {
      body = RefreshIndicator(
        onRefresh: () => ref.read(feedProvider.notifier).refresh(),
        child: body,
      );
    }

    return Scaffold(
      body: body,
      floatingActionButton: Column(
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
      ),
    );
  }

  Widget _buildFetchIndicator(
      BuildContext context, FeedState feed, SettingsState settings) {
    final total = settings.fetchIntervalSeconds;
    final remaining = feed.isFetching ? 0 : _remainingSeconds.clamp(0, total);
    final progress = total > 0 ? remaining / total : 0.0;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: feed.isFetching
                ? const CircularProgressIndicator(strokeWidth: 2)
                : CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
          ),
          const SizedBox(width: 4),
          Text(
            feed.isFetching ? '...' : '$remaining/$total',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (feed.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '+${feed.pendingCount}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
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
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.rss_feed, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'OmniVerse',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'アカウントを追加してタイムラインを取得しましょう',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AccountsScreen()),
                      );
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('アカウント追加'),
                  ),
                ],
              ),
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
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.rss_feed, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'OmniVerse',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '設定画面でフェッチを有効にしてください',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      );
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('設定を開く'),
                  ),
                ],
              ),
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

    // フィルタ適用
    final hideRtIds = settings.hideRetweetsAccountIds;
    var filteredPosts = feed.posts.toList();

    // 無効アカウントの投稿を除外
    if (enabledAccountIds.length < accounts.length) {
      filteredPosts = filteredPosts
          .where((p) =>
              p.accountId == null || enabledAccountIds.contains(p.accountId))
          .toList();
    }

    // RT 非表示フィルタ
    if (hideRtIds.isNotEmpty) {
      filteredPosts = filteredPosts
          .where((p) =>
              !p.isRetweet ||
              p.accountId == null ||
              !hideRtIds.contains(p.accountId))
          .toList();
    }

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
            String? accountHandle;
            if (post.accountId != null) {
              final account =
                  AccountStorageService.instance.getAccount(post.accountId!);
              if (account != null) accountHandle = account.handle;
            }
            final postCard = PostCard(
              key: ValueKey(post.id),
              post: post,
              accountHandle: accountHandle,
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
            );

            if (_animatingPostIds.contains(post.id)) {
              return _AnimatedPostCard(
                key: ValueKey('anim_${post.id}'),
                onAnimationComplete: () {
                  _animatingPostIds.remove(post.id);
                },
                child: postCard,
              );
            }
            return postCard;
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
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
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
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: widget.child,
      ),
    );
  }
}
