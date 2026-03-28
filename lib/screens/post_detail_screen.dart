import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' as share_plus;

import '../utils/image_headers.dart';
import '../models/account.dart';
import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/bookmark_service.dart';
import '../services/x_api_service.dart';
import '../widgets/account_picker_modal.dart';
import '../widgets/post_card.dart';
import '../widgets/post_media.dart';
import '../widgets/sns_badge.dart';
import 'user_profile_screen.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final Post post;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  late Post _post;
  List<Post> _replies = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _loadReplies();
  }

  Future<void> _loadReplies() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final account = _getAccount();
      if (account == null) {
        setState(() {
          _isLoading = false;
          _error = 'アカウント情報が見つかりません';
        });
        return;
      }

      List<Post> posts;
      if (widget.post.source == SnsService.x) {
        final tweetId = widget.post.id.replaceFirst('x_', '');
        posts = await XApiService.instance.getTweetDetail(
          account.xCredentials,
          tweetId,
          accountId: account.id,
        );
      } else {
        // Bluesky - Post.uri に投稿者の DID を含む正しい AT URI が格納されている
        final postUri = widget.post.uri ??
            'at://${account.blueskyCredentials.did}/app.bsky.feed.post/${widget.post.id.replaceFirst('bsky_', '')}';
        posts = await BlueskyApiService.instance.getPostThread(
          account.blueskyCredentials,
          postUri,
          accountId: account.id,
        );
      }

      // Separate the main post from replies
      final replies = posts
          .where((p) => p.id != widget.post.id)
          .toList();

      setState(() {
        _replies = replies;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'リプライの取得に失敗しました: $e';
      });
    }
  }

  Account? _getAccount() {
    if (widget.post.accountId == null) return null;
    return AccountStorageService.instance.getAccount(widget.post.accountId!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('投稿詳細'),
        actions: [
          IconButton(
            icon: Icon(
              BookmarkService.instance.isBookmarked(widget.post.id)
                  ? Icons.bookmark
                  : Icons.bookmark_outline,
            ),
            onPressed: () async {
              await BookmarkService.instance.toggle(widget.post);
              setState(() {});
            },
          ),
          if (widget.post.permalink != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () {
                share_plus.Share.share(widget.post.permalink!);
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReplies,
        child: ListView(
          children: [
            // Main post (expanded)
            _buildMainPost(context),
            const Divider(height: 1),

            // Replies section
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _loadReplies,
                      child: const Text('リトライ'),
                    ),
                  ],
                ),
              )
            else if (_replies.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'リプライはありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'リプライ (${_replies.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              ..._replies.map(
                (reply) {
                  final s = ref.watch(settingsProvider);
                  return PostCard(
                    post: reply,
                    compactEngagement: s.compactEngagement,
                    imageMaxHeight: s.imagePreviewSize.singleImageMaxHeight,
                    imageGridHeight: s.imagePreviewSize.gridImageHeight,
                    videoHeight: s.imagePreviewSize.videoHeight,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PostDetailScreen(post: reply),
                        ),
                      );
                    },
                    onLike: () => _handleLike(reply),
                    onRepost: () => _handleRepost(reply),
                  );
                },
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildMainPost(BuildContext context) {
    final post = _post;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author header (タップでユーザープロフィールへ)
          GestureDetector(
            onTap: () => navigateToUserProfile(context, post: post),
            child: Row(
              children: [
                Hero(
                  tag: 'avatar_${post.id}',
                  child: CircleAvatar(
                    radius: 24,
                    backgroundImage: post.avatarUrl != null
                        ? CachedNetworkImageProvider(post.avatarUrl!, headers: kImageHeaders)
                        : null,
                    child: post.avatarUrl == null
                        ? Text(post.username.isNotEmpty
                            ? post.username[0].toUpperCase()
                            : '?')
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.username,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          SnsBadge(service: post.source),
                        ],
                      ),
                      Text(
                        post.handle,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Full text with tappable links
          LinkedText(
            text: post.body,
            style: const TextStyle(fontSize: 16, height: 1.5),
            selectable: true,
          ),

          // Images (shared widget - not PostCard!)
          if (post.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            PostImageGrid(imageUrls: post.imageUrls),
          ],

          // Video
          if (post.videoUrl != null && post.videoThumbnailUrl != null) ...[
            const SizedBox(height: 12),
            PostVideoThumbnail(
              videoUrl: post.videoUrl!,
              thumbnailUrl: post.videoThumbnailUrl!,
            ),
          ],

          // Quoted post
          if (post.quotedPost != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PostDetailScreen(post: post.quotedPost!),
                  ),
                );
              },
              child: _buildQuotedPost(context, post.quotedPost!),
            ),
          ],

          const SizedBox(height: 12),

          // Timestamp
          Text(
            _formatFullTimestamp(post.timestamp),
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),

          const SizedBox(height: 12),
          const Divider(),

          // Engagement counts
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _buildCountLabel(post.replyCount, 'リプライ'),
                const SizedBox(width: 24),
                _buildCountLabel(post.repostCount, 'リポスト'),
                const SizedBox(width: 24),
                _buildCountLabel(post.likeCount, 'いいね'),
              ],
            ),
          ),

          const Divider(),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(
                  post.isReposted ? Icons.repeat_on : Icons.repeat,
                  color: post.isReposted ? Colors.green : null,
                ),
                onPressed: () => _handleRepost(post),
                tooltip: 'リポスト',
              ),
              IconButton(
                icon: Icon(
                  post.isLiked ? Icons.favorite : Icons.favorite_outline,
                  color: post.isLiked ? Colors.red : null,
                ),
                onPressed: () => _handleLike(post),
                tooltip: 'いいね',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountLabel(int count, String label) {
    return Row(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ],
    );
  }

  Widget _buildQuotedPost(BuildContext context, Post quoted) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundImage: quoted.avatarUrl != null
                    ? CachedNetworkImageProvider(quoted.avatarUrl!,
                        headers: kImageHeaders)
                    : null,
                child: quoted.avatarUrl == null
                    ? Text(
                        quoted.username.isNotEmpty
                            ? quoted.username[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontSize: 10),
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  quoted.username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  quoted.handle,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              SnsBadge(service: quoted.source),
            ],
          ),
          if (quoted.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            LinkedText(
              text: quoted.body,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
          if (quoted.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: PostImageGrid(imageUrls: quoted.imageUrls),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<Account?> _resolveAccount(Post post, String actionLabel) async {
    final settings = ref.read(settingsProvider);
    if (settings.showAccountPickerOnEngagement) {
      return showAccountPickerModal(
        context,
        service: post.source,
        actionLabel: actionLabel,
      );
    }
    return _getAccount();
  }

  void _updatePost({bool? isLiked, int? likeCount, bool? isReposted, int? repostCount}) {
    setState(() {
      _post = _post.copyWith(
        isLiked: isLiked ?? _post.isLiked,
        likeCount: likeCount ?? _post.likeCount,
        isReposted: isReposted ?? _post.isReposted,
        repostCount: repostCount ?? _post.repostCount,
      );
    });
    // メインタイムラインのstateにも反映
    ref.read(feedProvider.notifier).updatePostEngagement(
      _post.id,
      isLiked: isLiked,
      likeCount: likeCount,
      isReposted: isReposted,
      repostCount: repostCount,
    );
  }

  Future<void> _handleLike(Post post) async {
    final account = await _resolveAccount(post, 'いいね');
    if (account == null) return;

    final settings = ref.read(settingsProvider);
    final wasLiked = settings.showAccountPickerOnEngagement ? false : post.isLiked;
    final action = wasLiked ? ActivityAction.unlike : ActivityAction.like;
    final postSummary = post.body.length > 40 ? '${post.body.substring(0, 40)}…' : post.body;

    if (!settings.showAccountPickerOnEngagement) {
      _updatePost(
        isLiked: !wasLiked,
        likeCount: wasLiked ? post.likeCount - 1 : post.likeCount + 1,
      );
    }

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
            final result = await BlueskyApiService.instance.likePost(creds, postUri, postCid);
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

      if (!success && !settings.showAccountPickerOnEngagement) {
        _updatePost(isLiked: wasLiked, likeCount: post.likeCount);
      }
    } catch (e) {
      if (!settings.showAccountPickerOnEngagement) {
        _updatePost(isLiked: wasLiked, likeCount: post.likeCount);
      }
    }
  }

  Future<void> _handleRepost(Post post) async {
    final account = await _resolveAccount(post, 'リポスト');
    if (account == null) return;

    final settings = ref.read(settingsProvider);
    final wasReposted = settings.showAccountPickerOnEngagement ? false : post.isReposted;
    final action = wasReposted ? ActivityAction.unrepost : ActivityAction.repost;
    final postSummary = post.body.length > 40 ? '${post.body.substring(0, 40)}…' : post.body;

    if (!settings.showAccountPickerOnEngagement) {
      _updatePost(
        isReposted: !wasReposted,
        repostCount: wasReposted ? post.repostCount - 1 : post.repostCount + 1,
      );
    }

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
            final result = await BlueskyApiService.instance.repost(creds, postUri, postCid);
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

      if (!success && !settings.showAccountPickerOnEngagement) {
        _updatePost(isReposted: wasReposted, repostCount: post.repostCount);
      }
    } catch (e) {
      if (!settings.showAccountPickerOnEngagement) {
        _updatePost(isReposted: wasReposted, repostCount: post.repostCount);
      }
    }
  }

  String _formatFullTimestamp(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
