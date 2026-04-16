import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/engagement_errors.dart';
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
import '../services/engagement_service.dart';
import '../services/x_api_service.dart';
import '../widgets/account_picker_modal.dart';
import '../widgets/empty_state.dart';
import '../widgets/post_card.dart';
import 'compose_screen.dart';
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
  List<Post> _parents = [];
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

      // メイン投稿を最新データで更新
      final freshMain = posts.firstWhere(
        (p) => p.id == widget.post.id,
        orElse: () => _post,
      );

      // メイン投稿を基準に、親（文脈）とリプライを分離
      final mainId = widget.post.id;
      final mainIndex = posts.indexWhere((p) => p.id == mainId);

      List<Post> parents;
      List<Post> replies;

      if (mainIndex >= 0) {
        // APIの返却順序を信頼: mainより前が親、後がリプライ
        parents = posts.sublist(0, mainIndex);
        replies = mainIndex + 1 < posts.length ? posts.sublist(mainIndex + 1) : [];
      } else {
        // メイン投稿が見つからない場合のフォールバック
        final others = posts.where((p) => p.id != mainId).toList();
        if (widget.post.source == SnsService.x) {
          final mainNum = BigInt.tryParse(mainId.replaceFirst('x_', ''));
          replies = others.where((p) {
            final pNum = BigInt.tryParse(p.id.replaceFirst('x_', ''));
            return mainNum != null && pNum != null && pNum > mainNum;
          }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          final replyIds = replies.map((p) => p.id).toSet();
          parents = others.where((p) => !replyIds.contains(p.id)).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        } else {
          replies = others.where((p) => p.timestamp.isAfter(widget.post.timestamp)).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          final replyIds = replies.map((p) => p.id).toSet();
          parents = others.where((p) => !replyIds.contains(p.id)).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        }
      }

      setState(() {
        _post = freshMain;
        _parents = parents;
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
          if (widget.post.permalink != null)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              tooltip: '公式アプリで開く',
              onPressed: () {
                final uri = Uri.tryParse(widget.post.permalink!);
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReplies,
        child: Builder(builder: (context) {
          // スレッド全体のメディアURLを収集（メイン投稿 + リプライ）
          final threadImages = <String>[
            ..._post.imageUrls,
            for (final reply in _replies) ...reply.imageUrls,
          ];
          // 各投稿のオフセットを計算
          final replyOffsets = <String, int>{};
          var offset = _post.imageUrls.length;
          for (final reply in _replies) {
            replyOffsets[reply.id] = offset;
            offset += reply.imageUrls.length;
          }
          final useThread = threadImages.length > _post.imageUrls.length;

          return ListView(
          children: [
            // 親投稿（会話の文脈）
            if (_parents.isNotEmpty) ...[
              ..._parents.map((parent) {
                final s = ref.watch(settingsProvider);
                return PostCard(
                  post: parent,
                  sensitiveMode: s.sensitiveMode,
                  compactEngagement: s.compactEngagement,
                  imageMaxHeight: s.imagePreviewSize.singleImageMaxHeight,
                  imageGridHeight: s.imagePreviewSize.gridImageHeight,
                  videoHeight: s.imagePreviewSize.videoHeight,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(post: parent),
                      ),
                    );
                  },
                );
              }),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Row(
                  children: [
                    Container(
                      width: 2,
                      height: 16,
                      color: Colors.grey[300],
                    ),
                  ],
                ),
              ),
            ],
            // Main post (expanded)
            _buildMainPost(context, threadImages: useThread ? threadImages : null),
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
              const EmptyState(icon: Icons.chat_bubble_outline, title: 'リプライはありません')
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
                    threadImageUrls: useThread && reply.imageUrls.isNotEmpty ? threadImages : null,
                    threadIndexOffset: replyOffsets[reply.id] ?? 0,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PostDetailScreen(post: reply),
                        ),
                      );
                    },
                    onLike: () => _handleLike(reply),
                    onRepost: () => _handleRepost(reply),
                    onReply: () async {
                      final posted = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => ComposeScreen(inReplyToPost: reply),
                        ),
                      );
                      if (posted == true) _loadReplies();
                    },
                  );
                },
              ),
            ],
            const SizedBox(height: 80),
          ],
        );
        }),
      ),
    );
  }

  Widget _buildMainPost(BuildContext context, {List<String>? threadImages}) {
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
                          if (post.isProtected) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.lock, size: 14, color: Colors.grey[500]),
                          ],
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
            PostImageGrid(
              imageUrls: post.imageUrls,
              threadImageUrls: threadImages,
              threadIndexOffset: 0,
            ),
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

          // Action buttons with counts
          Builder(builder: (_) {
            final showCounts = post.replyCount > 0 || post.repostCount > 0 || post.likeCount > 0;
            return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildActionWithCount(
                icon: const Icon(Icons.chat_bubble_outline),
                count: post.replyCount,
                showCounts: showCounts,
                onPressed: () async {
                  final posted = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ComposeScreen(inReplyToPost: post),
                    ),
                  );
                  if (posted == true) _loadReplies();
                },
              ),
              _buildActionWithCount(
                icon: _AnimatedActionIcon(
                  engagementState: post.repostState(),
                  icon: Icons.repeat,
                  activeIcon: Icons.repeat_on,
                  activeColor: Colors.green,
                  useRotation: true,
                ),
                count: post.repostCount,
                showCounts: showCounts,
                onPressed: () => _showRepostMenu(post),
              ),
              _buildActionWithCount(
                icon: _AnimatedActionIcon(
                  engagementState: post.likeState(),
                  icon: Icons.favorite_outline,
                  activeIcon: Icons.favorite,
                  activeColor: Colors.red,
                ),
                count: post.likeCount,
                showCounts: showCounts,
                onPressed: () => _handleLike(post),
              ),
            ],
          ); }),
        ],
      ),
    );
  }

  Widget _buildActionWithCount({
    required Widget icon,
    required int count,
    required VoidCallback onPressed,
    required bool showCounts,
  }) {
    if (!showCounts) return IconButton(icon: icon, onPressed: onPressed);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: icon, onPressed: onPressed),
        Text(
          count > 0 ? count.toString() : '',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
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
    return showAccountPickerModal(
      context,
      service: post.source,
      actionLabel: actionLabel,
      fetchedByAccountIds: post.fetchedByAccountIds,
      likedByAccountIds: post.likedByAccountIds,
      repostedByAccountIds: post.repostedByAccountIds,
    );
  }

  void _showRepostMenu(Post post) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('リポスト'),
              onTap: () {
                Navigator.of(ctx).pop();
                _handleRepost(post);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('引用リポスト'),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(quotedPost: post),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _updatePost({
    String? accountId,
    bool? liked,
    int? likeCount,
    bool? reposted,
    int? repostCount,
  }) {
    setState(() {
      var newLikedBy = Set<String>.of(_post.likedByAccountIds);
      var newRepostedBy = Set<String>.of(_post.repostedByAccountIds);
      if (accountId != null) {
        if (liked == true) newLikedBy.add(accountId);
        if (liked == false) newLikedBy.remove(accountId);
        if (reposted == true) newRepostedBy.add(accountId);
        if (reposted == false) newRepostedBy.remove(accountId);
      }
      _post = _post.copyWith(
        likedByAccountIds: newLikedBy,
        repostedByAccountIds: newRepostedBy,
        likeCount: likeCount ?? _post.likeCount,
        repostCount: repostCount ?? _post.repostCount,
      );
    });
    // メインタイムラインのstateにも反映
    ref.read(feedProvider.notifier).updatePostEngagement(
      _post.id,
      accountId: accountId,
      liked: liked,
      likeCount: likeCount,
      reposted: reposted,
      repostCount: repostCount,
    );
  }

  Future<void> _handleLike(Post post) async {
    HapticFeedback.lightImpact();
    final account = await _resolveAccount(post, 'いいね');
    if (account == null) return;

    final willUnlike = post.isLikedBy(account.id);
    final action = willUnlike ? ActivityAction.unlike : ActivityAction.like;

    _updatePost(
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
      _updatePost(accountId: account.id, liked: willUnlike, likeCount: post.likeCount);
      ScaffoldMessenger.of(context).showSnackBar(
        engagementErrorSnackBar('いいね', result.statusCode),
      );
    }
  }

  Future<void> _handleRepost(Post post) async {
    HapticFeedback.lightImpact();
    final account = await _resolveAccount(post, 'リポスト');
    if (account == null) return;

    final willUnrepost = post.isRepostedBy(account.id);
    final action = willUnrepost ? ActivityAction.unrepost : ActivityAction.repost;

    _updatePost(
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
      _updatePost(accountId: account.id, reposted: willUnrepost, repostCount: post.repostCount);
      ScaffoldMessenger.of(context).showSnackBar(
        engagementErrorSnackBar('リポスト', result.statusCode),
      );
    }
  }

  String _formatFullTimestamp(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _AnimatedActionIcon extends StatefulWidget {
  const _AnimatedActionIcon({
    this.engagementState = EngagementState.none,
    required this.icon,
    required this.activeIcon,
    required this.activeColor,
    this.useRotation = false,
    this.size = 24.0,
  });

  final EngagementState engagementState;
  final IconData icon;
  final IconData activeIcon;
  final Color activeColor;
  final bool useRotation;
  final double size;

  @override
  State<_AnimatedActionIcon> createState() => _AnimatedActionIconState();
}

class _AnimatedActionIconState extends State<_AnimatedActionIcon>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _rotationController;
  late Animation<double> _scaleAnimation;
  bool _rotateForward = true;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = _buildActivateScale();
  }

  Animation<double> _buildActivateScale() {
    return TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.95), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
  }

  Animation<double> _buildDeactivateScale() {
    return TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant _AnimatedActionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.engagementState != oldWidget.engagementState) {
      final oldState = oldWidget.engagementState;
      final newState = widget.engagementState;
      if (newState == EngagementState.all && oldState != EngagementState.all) {
        // none/partial -> all: activate animation
        _scaleAnimation = _buildActivateScale();
        _scaleController.forward(from: 0);
        if (widget.useRotation) {
          _rotateForward = true;
          _rotationController.forward(from: 0);
        }
      } else if (newState == EngagementState.partial && oldState == EngagementState.none) {
        // none -> partial: activate animation
        _scaleAnimation = _buildActivateScale();
        _scaleController.forward(from: 0);
        if (widget.useRotation) {
          _rotateForward = true;
          _rotationController.forward(from: 0);
        }
      } else if (newState == EngagementState.none && oldState != EngagementState.none) {
        // all/partial -> none: deactivate animation
        _scaleAnimation = _buildDeactivateScale();
        _scaleController.forward(from: 0);
        if (widget.useRotation) {
          _rotateForward = false;
          _rotationController.forward(from: 0);
        }
      }
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final IconData iconData;
    final Color? color;
    switch (widget.engagementState) {
      case EngagementState.all:
        iconData = widget.activeIcon;
        color = widget.activeColor;
      case EngagementState.partial:
        iconData = widget.icon; // outline icon
        color = widget.activeColor; // colored outline
      case EngagementState.none:
        iconData = widget.icon;
        color = null;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_scaleAnimation, _rotationController]),
      builder: (context, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: Transform.rotate(
          angle: widget.useRotation
              ? _rotationController.value * 2 * 3.14159 * (_rotateForward ? 1 : -1)
              : 0,
          child: child,
        ),
      ),
      child: Icon(iconData, size: widget.size, color: color),
    );
  }
}
