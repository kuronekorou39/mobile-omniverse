import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_api_service.dart';
import '../utils/image_headers.dart';
import '../widgets/post_card.dart';
import '../widgets/sns_badge.dart';
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
  List<Post> _posts = [];
  String? _profileError;
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
            setState(() {
              _xRestId = profile['rest_id'] as String?;
              _bio = profile['description'] as String?;
              _followersCount = profile['followers_count'] as int?;
              _followingCount = profile['friends_count'] as int?;
              _postsCount = profile['statuses_count'] as int?;
            });
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
            _posts = result.posts;
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
    if (_isLoadingMore || !_hasMore || _nextCursor == null) return;
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
            _posts = [..._posts, ...result.posts];
            _nextCursor = result.cursor;
            _hasMore = result.cursor != null && result.posts.isNotEmpty;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[UserProfile] Error loading more posts: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Text(widget.handle),
            floating: true,
            snap: true,
            forceElevated: innerBoxIsScrolled,
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
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // 投稿タブ
            _buildPostList(_posts),
            // メディアタブ (ページネーションは投稿タブ側で処理)
            _buildPostList(_mediaPosts, isMediaTab: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPostList(List<Post> posts, {bool isMediaTab = false}) {
    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_postsError != null) {
      return Center(
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
      );
    }
    if (posts.isEmpty) {
      return const Center(
        child: Text('投稿はありません', style: TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await _loadData();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (!isMediaTab &&
              notification is ScrollEndNotification &&
              notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 200) {
            _loadMorePosts();
          }
          return false;
        },
        child: ListView.builder(
          itemCount: posts.length + (_hasMore && !isMediaTab ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= posts.length) {
              // ローディングインジケータ
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
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PostDetailScreen(post: post),
                  ),
                );
              },
              onLike: () => _handleLike(post),
              onRepost: () => _handleRepost(post),
            );
          },
        ),
      ),
    );
  }

  // ===== エンゲージメント =====

  void _updatePost(Post post, {bool? isLiked, int? likeCount, bool? isReposted, int? repostCount}) {
    setState(() {
      _posts = _posts.map((p) {
        if (p.id != post.id) return p;
        return p.copyWith(
          isLiked: isLiked ?? p.isLiked,
          likeCount: likeCount ?? p.likeCount,
          isReposted: isReposted ?? p.isReposted,
          repostCount: repostCount ?? p.repostCount,
        );
      }).toList();
    });
  }

  Future<void> _handleLike(Post post) async {
    final account = _account;
    if (account == null) return;

    final wasLiked = post.isLiked;
    final action = wasLiked ? ActivityAction.unlike : ActivityAction.like;
    final postSummary = post.body.length > 40
        ? '${post.body.substring(0, 40)}...'
        : post.body;

    // Optimistic update
    _updatePost(post,
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
        _updatePost(post, isLiked: wasLiked, likeCount: post.likeCount);
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
      _updatePost(post, isLiked: wasLiked, likeCount: post.likeCount);
    }
  }

  Future<void> _handleRepost(Post post) async {
    final account = _account;
    if (account == null) return;

    final wasReposted = post.isReposted;
    final action = wasReposted ? ActivityAction.unrepost : ActivityAction.repost;
    final postSummary = post.body.length > 40
        ? '${post.body.substring(0, 40)}...'
        : post.body;

    _updatePost(post,
      isReposted: !wasReposted,
      repostCount: wasReposted ? post.repostCount - 1 : post.repostCount + 1,
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
        _updatePost(post, isReposted: wasReposted, repostCount: post.repostCount);
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
      _updatePost(post, isReposted: wasReposted, repostCount: post.repostCount);
    }
  }

  Widget _buildProfileHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              CircleAvatar(
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
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),

          // Username
          Text(
            widget.username,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),

          // Handle + badge
          Row(
            children: [
              SnsBadge(service: widget.service),
              const SizedBox(width: 6),
              Text(
                widget.handle,
                style: TextStyle(color: Colors.grey[600], fontSize: 15),
              ),
            ],
          ),

          // Bio
          if (_bio != null && _bio!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_bio!, style: const TextStyle(fontSize: 14)),
          ],

          // Stats
          if (_followersCount != null || _followingCount != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (_followingCount != null)
                  _buildStat(_followingCount!, 'フォロー'),
                if (_followingCount != null && _followersCount != null)
                  const SizedBox(width: 16),
                if (_followersCount != null)
                  _buildStat(_followersCount!, 'フォロワー'),
                if (_postsCount != null) ...[
                  const SizedBox(width: 16),
                  _buildStat(_postsCount!, '投稿'),
                ],
              ],
            ),
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
