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
  String? _followUri; // Bluesky: non-null = following
  bool _isFollowing = false;
  bool _isLoadingProfile = true;
  bool _isLoadingPosts = true;
  bool _isFollowLoading = false;
  List<Post> _posts = [];
  String? _profileError;
  String? _postsError;

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
            final viewer = profile['viewer'] as Map<String, dynamic>?;
            _followUri = viewer?['following'] as String?;
            _isFollowing = _followUri != null;
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
              _isFollowing = profile['is_following'] as bool? ?? false;
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
        final posts = await BlueskyApiService.instance.getAuthorFeed(
          account.blueskyCredentials,
          actor,
          accountId: account.id,
        );
        if (mounted) {
          setState(() {
            _posts = posts;
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
        final posts = await XApiService.instance.getUserTimeline(
          account.xCredentials,
          _xRestId!,
          accountId: account.id,
        );
        if (mounted) {
          setState(() {
            _posts = posts;
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

  Future<void> _toggleFollow() async {
    final account = _account;
    if (account == null) return;

    final wasFollowing = _isFollowing;
    final action = wasFollowing ? ActivityAction.unfollow : ActivityAction.follow;

    setState(() => _isFollowLoading = true);

    try {
      if (account.service == SnsService.bluesky) {
        if (wasFollowing && _followUri != null) {
          final ok = await BlueskyApiService.instance
              .unfollow(account.blueskyCredentials, _followUri!);
          _logAction(action, account, ok,
              targetId: widget.handle, targetSummary: widget.username);
          if (ok && mounted) {
            setState(() {
              _isFollowing = false;
              _followUri = null;
              if (_followersCount != null) _followersCount = _followersCount! - 1;
            });
          }
        } else {
          final actor = widget.handle.replaceFirst('@', '');
          final profile = await BlueskyApiService.instance
              .getProfile(account.blueskyCredentials, actor);
          final did = profile?['did'] as String?;
          if (did != null) {
            final uri = await BlueskyApiService.instance
                .follow(account.blueskyCredentials, did);
            final ok = uri != null;
            _logAction(action, account, ok,
                targetId: widget.handle, targetSummary: widget.username);
            if (ok && mounted) {
              setState(() {
                _isFollowing = true;
                _followUri = uri;
                if (_followersCount != null) _followersCount = _followersCount! + 1;
              });
            }
          } else {
            _logAction(action, account, false,
                targetId: widget.handle, error: 'DID取得失敗');
          }
        }
      } else if (account.service == SnsService.x) {
        if (_xRestId == null) return;
        if (wasFollowing) {
          final ok = await XApiService.instance
              .unfollowUser(account.xCredentials, _xRestId!);
          _logAction(action, account, ok,
              targetId: widget.handle, targetSummary: widget.username);
          if (ok && mounted) {
            setState(() {
              _isFollowing = false;
              if (_followersCount != null) _followersCount = _followersCount! - 1;
            });
          }
        } else {
          final ok = await XApiService.instance
              .followUser(account.xCredentials, _xRestId!);
          _logAction(action, account, ok,
              targetId: widget.handle, targetSummary: widget.username);
          if (ok && mounted) {
            setState(() {
              _isFollowing = true;
              if (_followersCount != null) _followersCount = _followersCount! + 1;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[UserProfile] Follow error: $e');
      _logAction(action, account, false,
          targetId: widget.handle, error: '$e');
    }

    if (mounted) setState(() => _isFollowLoading = false);
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
            // メディアタブ
            _buildPostList(_mediaPosts),
          ],
        ),
      ),
    );
  }

  Widget _buildPostList(List<Post> posts) {
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
      child: ListView.builder(
        itemCount: posts.length,
        itemBuilder: (context, index) {
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
          );
        },
      ),
    );
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
              // フォローボタン (両サービス対応)
              if (!_isLoadingProfile)
                _isFollowLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _isFollowing
                        ? OutlinedButton(
                            onPressed: _toggleFollow,
                            child: const Text('フォロー中'),
                          )
                        : FilledButton(
                            onPressed: _toggleFollow,
                            child: const Text('フォロー'),
                          ),
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
