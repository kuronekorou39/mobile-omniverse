import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/account.dart';
import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../providers/activity_log_provider.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/engagement_service.dart';
import '../services/x_api_service.dart';
import '../utils/engagement_errors.dart';
import '../utils/image_headers.dart';
import '../providers/settings_provider.dart';
import '../widgets/account_picker_modal.dart';
import '../widgets/image_viewer.dart';
import '../widgets/empty_state.dart';
import '../widgets/post_card.dart';
import '../widgets/sns_badge.dart';
import 'compose_screen.dart';
import 'post_detail_screen.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.username,
    required this.handle,
    required this.service,
    this.avatarUrl,
    this.accountId,
  });

  final String username;
  final String handle;
  final SnsService service;
  final String? avatarUrl;
  final String? accountId;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  String? _bio;
  int? _followersCount;
  int? _followingCount;
  int? _postsCount;
  bool _isLoadingProfile = true;
  bool _isLoadingPosts = true;
  bool _isLoadingMore = false;
  bool _loadMoreError = false;
  List<Post> _posts = [];
  String? _bannerUrl;
  String? _profileError;
  bool _hideRetweets = false;
  String? _postsError;
  String? _nextCursor;
  bool _hasMore = true;

  // X 用
  String? _xRestId;

  late final TabController _tabController;

  Account? get _account {
    if (widget.accountId == null) return null;
    return AccountStorageService.instance.getAccount(widget.accountId!);
  }

  List<Post> get _mediaPosts => _posts
      .where((p) => p.imageUrls.isNotEmpty || p.videoUrl != null)
      .toList();

  void _logAction(
    ActivityAction action,
    Account account,
    bool success, {
    String? targetId,
    String? targetSummary,
    String? error,
    int? statusCode,
  }) {
    ref.read(activityLogProvider.notifier).logAction(
      action: action,
      platform: account.service,
      accountHandle: account.handle,
      accountId: account.id,
      targetId: targetId,
      targetSummary: targetSummary,
      success: success,
      statusCode: statusCode,
      errorMessage: error,
    );
  }

  /// UserTweets APIではユーザーデータが省略されることがあるため、
  /// プロフィール情報で補完する
  List<Post> _backfillUserData(List<Post> posts) {
    return posts.map((p) {
      if (p.username.isEmpty || p.handle == '@') {
        return p.copyWith(
          username: widget.username,
          handle: widget.handle,
          avatarUrl: widget.avatarUrl,
        );
      }
      return p;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _nextCursor = null;
      _hasMore = true;
      _loadMoreError = false;
    });
    await _loadProfile();
    if (mounted) _loadPosts();
  }

  Future<void> _loadProfile() async {
    final account = _account;
    if (account == null) {
      debugPrint('[UserProfile] _loadProfile: account is null (accountId=${widget.accountId})');
      setState(() {
        _isLoadingProfile = false;
        _profileError = 'アカウント情報が見つかりません';
      });
      return;
    }

    debugPrint('[UserProfile] _loadProfile: service=${account.service}, handle=${widget.handle}');

    try {
      if (account.service == SnsService.bluesky) {
        final actor = widget.handle.replaceFirst('@', '');
        final profile = await BlueskyApiService.instance
            .getProfile(account.blueskyCredentials, actor);
        if (profile != null && mounted) {
          setState(() {
            _bio = profile['description'] as String?;
            _followersCount = profile['followersCount'] as int?;
            _followingCount = profile['followsCount'] as int?;
            _postsCount = profile['postsCount'] as int?;
          });
          _logAction(ActivityAction.profileFetch, account, true,
              targetId: actor);
        } else if (mounted) {
          setState(() => _profileError = 'プロフィールを取得できませんでした');
          _logAction(ActivityAction.profileFetch, account, false,
              targetId: actor, error: 'プロフィールがnull');
        }
      } else if (account.service == SnsService.x) {
        final screenName = widget.handle.replaceFirst('@', '');
        try {
          final profile = await XApiService.instance
              .getUserProfile(account.xCredentials, screenName);
          if (profile != null && mounted) {
            final isProtected = profile['protected'] as bool? ?? false;
            setState(() {
              _xRestId = profile['rest_id'] as String?;
              _bio = profile['description'] as String?;
              _followersCount = profile['followers_count'] as int?;
              _followingCount = profile['friends_count'] as int?;
              _postsCount = profile['statuses_count'] as int?;
              _bannerUrl = profile['profile_banner_url'] as String?;
            });
            // 自アカウントのprotected状態を保存
            if (widget.accountId != null) {
              ref.read(accountProvider.notifier).updateProtectedStatus(widget.accountId!, isProtected);
            }
            _logAction(ActivityAction.profileFetch, account, true,
                targetId: screenName);
          } else if (mounted) {
            setState(() => _profileError = 'プロフィールを取得できませんでした');
            _logAction(ActivityAction.profileFetch, account, false,
                targetId: screenName, error: 'プロフィールがnull');
          }
        } on XApiException catch (e) {
          debugPrint('[UserProfile] XApiException loading profile: $e');
          if (mounted) setState(() => _profileError = '$e');
          _logAction(ActivityAction.profileFetch, account, false,
              targetId: screenName, error: '$e');
        }
      }
    } catch (e) {
      debugPrint('[UserProfile] Error loading profile: $e');
      if (mounted) setState(() => _profileError = '$e');
      _logAction(ActivityAction.profileFetch, account, false,
          error: '$e');
    }

    if (mounted) setState(() => _isLoadingProfile = false);
  }

  Future<void> _loadPosts() async {
    final account = _account;
    if (account == null) {
      setState(() {
        _isLoadingPosts = false;
        _postsError = 'アカウント情報が見つかりません';
      });
      return;
    }

    try {
      if (account.service == SnsService.bluesky) {
        final actor = widget.handle.replaceFirst('@', '');
        final result = await BlueskyApiService.instance.getAuthorFeed(
          account.blueskyCredentials,
          actor,
          accountId: account.id,
        );
        if (mounted) {
          setState(() {
            _posts = result.posts;
            _nextCursor = result.cursor;
            _hasMore = result.cursor != null;
            _isLoadingPosts = false;
          });
          return;
        }
      } else if (account.service == SnsService.x) {
        if (_xRestId == null) {
          if (mounted) {
            setState(() {
              _postsError = 'ユーザーIDを取得できませんでした';
              _isLoadingPosts = false;
            });
          }
          return;
        }
        final result = await XApiService.instance.getUserTimeline(
          account.xCredentials,
          _xRestId!,
          accountId: account.id,
        );
        if (mounted) {
          setState(() {
            _posts = _backfillUserData(result.posts);
            _nextCursor = result.cursor;
            _hasMore = result.cursor != null;
            _isLoadingPosts = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('[UserProfile] Error loading posts: $e');
      if (mounted) {
        setState(() {
          _postsError = '$e';
          _isLoadingPosts = false;
        });
        return;
      }
    }

    if (mounted) setState(() => _isLoadingPosts = false);
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMore || _nextCursor == null || _loadMoreError) return;
    final account = _account;
    if (account == null) return;

    setState(() => _isLoadingMore = true);

    try {
      if (account.service == SnsService.bluesky) {
        final actor = widget.handle.replaceFirst('@', '');
        final result = await BlueskyApiService.instance.getAuthorFeed(
          account.blueskyCredentials,
          actor,
          accountId: account.id,
          cursor: _nextCursor,
        );
        if (mounted) {
          setState(() {
            _posts = [..._posts, ...result.posts];
            _nextCursor = result.cursor;
            _hasMore = result.cursor != null && result.posts.isNotEmpty;
            _isLoadingMore = false;
          });
        }
      } else if (account.service == SnsService.x) {
        if (_xRestId == null) return;
        final result = await XApiService.instance.getUserTimeline(
          account.xCredentials,
          _xRestId!,
          accountId: account.id,
          cursor: _nextCursor,
        );
        if (mounted) {
          setState(() {
            _posts = [..._posts, ..._backfillUserData(result.posts)];
            _nextCursor = result.cursor;
            _hasMore = result.cursor != null && result.posts.isNotEmpty;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[UserProfile] Error loading more posts: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _loadMoreError = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('追加読み込みに失敗しました: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePosts = _tabController.index == 0
        ? (_hideRetweets ? _posts.where((p) => !p.isRetweet).toList() : _posts)
        : (_hideRetweets ? _mediaPosts.where((p) => !p.isRetweet).toList() : _mediaPosts);

    return Scaffold(
      body: _buildSliverBody(activePosts),
    );
  }

  Widget _buildSliverBody(List<Post> posts) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 200) {
          _loadMorePosts();
        }
        return false;
      },
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -300 && _tabController.index < _tabController.length - 1) {
            _tabController.animateTo(_tabController.index + 1);
          } else if (details.primaryVelocity! > 300 && _tabController.index > 0) {
            _tabController.animateTo(_tabController.index - 1);
          }
        },
        child: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(widget.handle),
            floating: true,
            snap: true,
            actions: [
              IconButton(
                icon: _hideRetweets
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CustomPaint(
                          painter: _StrikethroughPainter(),
                          child: Icon(Icons.repeat, size: 20, color: Colors.grey[500]),
                        ),
                      )
                    : const Icon(Icons.repeat, size: 20),
                tooltip: _hideRetweets ? 'RTを表示' : 'RTを非表示',
                onPressed: () => setState(() => _hideRetweets = !_hideRetweets),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 20),
                tooltip: '公式アプリで開く',
                onPressed: () {
                  final url = widget.service == SnsService.x
                      ? 'https://x.com/${widget.handle.replaceFirst('@', '')}'
                      : 'https://bsky.app/profile/${widget.handle.replaceFirst('@', '')}';
                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
              ),
            ],
          ),
          SliverToBoxAdapter(child: _buildProfileHeader()),
          SliverToBoxAdapter(
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '投稿'),
                Tab(text: 'メディア'),
              ],
            ),
          ),
          ..._buildPostSlivers(posts),
        ],
      ),
      ),
    );
  }

  List<Widget> _buildPostSlivers(List<Post> posts) {
    if (_isLoadingPosts) {
      return [
        const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_postsError != null) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    _postsError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _postsError = null;
                        _isLoadingPosts = true;
                      });
                      _loadPosts();
                    },
                    child: const Text('リトライ'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }
    if (posts.isEmpty) {
      return [
        const SliverFillRemaining(
          child: EmptyState(icon: Icons.article_outlined, title: '投稿はありません'),
        ),
      ];
    }
    final s = ref.watch(settingsProvider);
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= posts.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: _isLoadingMore
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const SizedBox.shrink(),
                ),
              );
            }
            final post = posts[index];
            return PostCard(
              post: post,
              sensitiveMode: s.sensitiveMode,
              compactEngagement: s.compactEngagement,
              imageMaxHeight: s.imagePreviewSize.singleImageMaxHeight,
              imageGridHeight: s.imagePreviewSize.gridImageHeight,
              videoHeight: s.imagePreviewSize.videoHeight,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PostDetailScreen(post: post),
                  ),
                );
              },
              onLike: () => _handleLike(post),
              onRepost: () => _handleRepost(post),
              onQuoteRepost: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(quotedPost: post),
                  ),
                );
              },
              onReply: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(inReplyToPost: post),
                  ),
                );
              },
            );
          },
          childCount: posts.length + (_hasMore ? 1 : 0),
        ),
      ),
    ];
  }

  // ===== エンゲージメント =====

  void _updatePost(Post post, {String? accountId, bool? liked, int? likeCount, bool? reposted, int? repostCount}) {
    setState(() {
      _posts = _posts.map((p) {
        if (p.id != post.id) return p;
        var newLikedBy = Set<String>.of(p.likedByAccountIds);
        var newRepostedBy = Set<String>.of(p.repostedByAccountIds);
        if (accountId != null) {
          if (liked == true) newLikedBy.add(accountId);
          if (liked == false) newLikedBy.remove(accountId);
          if (reposted == true) newRepostedBy.add(accountId);
          if (reposted == false) newRepostedBy.remove(accountId);
        }
        return p.copyWith(
          likedByAccountIds: newLikedBy,
          repostedByAccountIds: newRepostedBy,
          likeCount: likeCount ?? p.likeCount,
          repostCount: repostCount ?? p.repostCount,
        );
      }).toList();
    });
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

    final wasLiked = post.isLikedBy(account.id);
    final action = wasLiked ? ActivityAction.unlike : ActivityAction.like;

    _updatePost(post,
      accountId: account.id,
      liked: !wasLiked,
      likeCount: wasLiked ? post.likeCount - 1 : post.likeCount + 1,
    );

    final result = await EngagementService.instance.like(
      post: post, account: account, unlike: wasLiked,
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
      _updatePost(post, accountId: account.id, liked: wasLiked, likeCount: post.likeCount);
      ScaffoldMessenger.of(context).showSnackBar(
        engagementErrorSnackBar('いいね', result.statusCode),
      );
    }
  }

  Future<void> _handleRepost(Post post) async {
    HapticFeedback.lightImpact();
    final account = await _resolveAccount(post, 'リポスト');
    if (account == null) return;

    final wasReposted = post.isRepostedBy(account.id);
    final action = wasReposted ? ActivityAction.unrepost : ActivityAction.repost;

    _updatePost(post,
      accountId: account.id,
      reposted: !wasReposted,
      repostCount: wasReposted ? post.repostCount - 1 : post.repostCount + 1,
    );

    final result = await EngagementService.instance.repost(
      post: post, account: account, unrepost: wasReposted,
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
      _updatePost(post, accountId: account.id, reposted: wasReposted, repostCount: post.repostCount);
      ScaffoldMessenger.of(context).showSnackBar(
        engagementErrorSnackBar('リポスト', result.statusCode),
      );
    }
  }

  void _openImageViewer(List<String> urls) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => ImageViewer(imageUrls: urls),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner image
        if (_bannerUrl != null)
          GestureDetector(
            onTap: () => _openImageViewer([_bannerUrl!]),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: _bannerUrl!,
                httpHeaders: kImageHeaders,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[300],
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[300],
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 120,
            width: double.infinity,
            child: Container(color: Colors.grey[300]),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar
                  GestureDetector(
                    onTap: widget.avatarUrl != null
                        ? () => _openImageViewer([widget.avatarUrl!])
                        : null,
                    child: CircleAvatar(
                      radius: 36,
                      backgroundImage: widget.avatarUrl != null
                          ? CachedNetworkImageProvider(widget.avatarUrl!,
                              headers: kImageHeaders)
                          : null,
                      child: widget.avatarUrl == null
                          ? Text(
                              widget.username.isNotEmpty
                                  ? widget.username[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 28),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Name + Handle + Stats
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.username,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            SnsBadge(service: widget.service),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.handle,
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (_followersCount != null || _followingCount != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (_followingCount != null)
                                _buildStat(_followingCount!, 'フォロー'),
                              if (_followingCount != null && _followersCount != null)
                                const SizedBox(width: 12),
                              if (_followersCount != null)
                                _buildStat(_followersCount!, 'フォロワー'),
                              if (_postsCount != null) ...[
                                const SizedBox(width: 12),
                                _buildStat(_postsCount!, '投稿'),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // Bio
              if (_bio != null && _bio!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_bio!, style: const TextStyle(fontSize: 14)),
              ],

              if (_isLoadingProfile) ...[
                const SizedBox(height: 12),
                const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],

              if (_profileError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _profileError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStat(int count, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatCount(count),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

/// PostCard のアバタータップで使う簡易ファクトリ
void navigateToUserProfile(
  BuildContext context, {
  required Post post,
}) {
  // ユーザーデータが揃っている → 即遷移
  if (post.username.isNotEmpty && post.handle != '@') {
    _pushProfileScreen(context, post);
    return;
  }

  // ユーザーデータが欠けている → ツイート詳細から取得を試みる
  _fetchThenNavigate(context, post);
}

void _pushProfileScreen(BuildContext context, Post post) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => UserProfileScreen(
        username: post.username,
        handle: post.handle,
        service: post.source,
        avatarUrl: post.avatarUrl,
        accountId: post.accountId,
      ),
    ),
  );
}

/// ユーザーデータが欠けた投稿のツイート詳細を取得し、
/// ユーザー情報を補完してからプロフィール画面に遷移する
Future<void> _fetchThenNavigate(BuildContext context, Post post) async {
  // accountId から使えるアカウントを探す
  Account? account;
  if (post.accountId != null) {
    account = AccountStorageService.instance.getAccount(post.accountId!);
  }
  // accountId で見つからなければ同じサービスの有効アカウントを探す
  account ??= AccountStorageService.instance.accounts
      .where((a) => a.service == post.source && a.isEnabled)
      .firstOrNull;

  if (account == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ユーザー情報を取得できません')),
      );
    }
    return;
  }

  // ローディング表示（ルートNavigatorで表示）
  showDialog(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final tweetId = post.id.replaceFirst('x_', '');
    List<Post> fetched;

    if (post.source == SnsService.x) {
      fetched = await XApiService.instance.getTweetDetail(
        account.xCredentials, tweetId, accountId: account.id,
      );
    } else {
      fetched = await BlueskyApiService.instance.getPostThread(
        account.blueskyCredentials, tweetId, accountId: account.id,
      );
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // ローディングを閉じる

    // 取得した投稿からユーザー情報を取り出す
    final found = fetched.where((p) => p.id == post.id).firstOrNull;
    if (found != null && found.username.isNotEmpty && found.handle != '@') {
      _pushProfileScreen(context, found);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ユーザー情報を取得できません')),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // ローディングを閉じる
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('取得失敗: $e')),
    );
  }
}

/// アイコンの上に斜線を引くPainter
class _StrikethroughPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(2, size.height - 2),
      Offset(size.width - 2, 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
