import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/account.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../utils/image_headers.dart';
import '../widgets/post_card.dart';
import '../widgets/sns_badge.dart';
import 'post_detail_screen.dart';

class UserProfileScreen extends StatefulWidget {
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
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
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

  Account? get _account {
    if (widget.accountId == null) return null;
    return AccountStorageService.instance.getAccount(widget.accountId!);
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPosts();
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
        // handle から @ を除去
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
        } else if (mounted) {
          setState(() => _profileError = 'プロフィールを取得できませんでした');
        }
      }
      // X のプロフィール API は未実装（GraphQL UserByScreenName が必要）
    } catch (e) {
      debugPrint('[UserProfile] Error loading profile: $e');
      if (mounted) setState(() => _profileError = '$e');
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
      }
      // X のユーザー TL は未実装
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
    if (account == null || account.service != SnsService.bluesky) return;

    setState(() => _isFollowLoading = true);

    try {
      if (_isFollowing && _followUri != null) {
        final ok = await BlueskyApiService.instance
            .unfollow(account.blueskyCredentials, _followUri!);
        if (ok && mounted) {
          setState(() {
            _isFollowing = false;
            _followUri = null;
            if (_followersCount != null) _followersCount = _followersCount! - 1;
          });
        }
      } else {
        // handle から DID を取得する必要があるが、プロフィール API から取得済みのはず
        // ここでは actor handle をそのまま DID として使う（プロフィール API が DID を返す場合）
        final actor = widget.handle.replaceFirst('@', '');
        // まずプロフィールから DID を取得
        final profile = await BlueskyApiService.instance
            .getProfile(account.blueskyCredentials, actor);
        final did = profile?['did'] as String?;
        if (did != null) {
          final uri = await BlueskyApiService.instance
              .follow(account.blueskyCredentials, did);
          if (uri != null && mounted) {
            setState(() {
              _isFollowing = true;
              _followUri = uri;
              if (_followersCount != null) _followersCount = _followersCount! + 1;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[UserProfile] Follow error: $e');
    }

    if (mounted) setState(() => _isFollowLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.handle)),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_loadProfile(), _loadPosts()]);
        },
        child: CustomScrollView(
          slivers: [
            // プロフィールヘッダー
            SliverToBoxAdapter(child: _buildProfileHeader()),
            const SliverToBoxAdapter(child: Divider()),

            // 投稿一覧
            if (_isLoadingPosts)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_postsError != null)
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
              )
            else if (_posts.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text('投稿はありません', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final post = _posts[index];
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
                  childCount: _posts.length,
                ),
              ),
          ],
        ),
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
              // フォローボタン (Bluesky のみ)
              if (widget.service == SnsService.bluesky && !_isLoadingProfile)
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
