import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/post.dart';
import '../screens/post_detail_screen.dart';
import '../screens/user_profile_screen.dart';
import '../services/account_storage_service.dart';
import '../utils/image_headers.dart';
import 'post_media.dart';
import 'sns_badge.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onLike,
    this.onRepost,
    this.onQuoteRepost,
    this.onReply,
    this.hideSensitive = true,
    this.compactEngagement = true,
    this.imageMaxHeight,
    this.imageGridHeight,
    this.videoHeight,
    this.hideUserInfo = false,
  });

  final Post post;
  final VoidCallback? onTap;
  final VoidCallback? onLike;
  final VoidCallback? onRepost;
  final VoidCallback? onQuoteRepost;
  final VoidCallback? onReply;
  final bool hideSensitive;
  final bool compactEngagement;
  final double? imageMaxHeight;
  final double? imageGridHeight;
  final double? videoHeight;
  final bool hideUserInfo;

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${timestamp.month}/${timestamp.day}';
  }

  void _showRepostMenu(BuildContext context) {
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
                Navigator.pop(ctx);
                onRepost?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: const Text('引用リポスト'),
              onTap: () {
                Navigator.pop(ctx);
                onQuoteRepost?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // RT header
              if (!hideUserInfo && post.isRetweet && post.retweetedByUsername != null) ...[
                _buildRetweetHeader(context),
                const SizedBox(height: 6),
              ],

              // Avatar + Content row (X-style layout)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!hideUserInfo) ...[
                    // 通常モード: アバター + コンテンツ
                    _buildAvatar(context),
                    const SizedBox(width: 10),
                  ] else ...[
                    // 匿名モード: 左余白にSNSバッジ（半透明）
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 8),
                      child: Opacity(
                        opacity: 0.5,
                        child: SnsBadge(service: post.source, size: 14),
                      ),
                    ),
                  ],
                  // Content column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name / Handle / Timestamp
                        if (!hideUserInfo) ...[
                          _buildNameRow(context),
                          const SizedBox(height: 4),
                        ],

                        // Body text, images, video
                        _SensitiveOverlay(
                          isSensitive: post.isSensitive && hideSensitive &&
                              (post.imageUrls.isNotEmpty || post.videoUrl != null),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (post.body.isNotEmpty)
                                LinkedText(
                                  text: post.body,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.45,
                                  ),
                                ),
                              if (post.imageUrls.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                PostImageGrid(
                                  imageUrls: post.imageUrls,
                                  maxSingleHeight: imageMaxHeight,
                                  gridHeight: imageGridHeight,
                                ),
                              ],
                              if (post.videoUrl != null && post.videoThumbnailUrl != null) ...[
                                const SizedBox(height: 8),
                                PostVideoThumbnail(
                                  videoUrl: post.videoUrl!,
                                  thumbnailUrl: post.videoThumbnailUrl!,
                                  height: videoHeight,
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Quoted post card
                        if (post.quotedPost != null) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PostDetailScreen(post: post.quotedPost!),
                                ),
                              );
                            },
                            child: _buildQuotedPostCard(context, post.quotedPost!),
                          ),
                        ],

                      ],
                    ),
                  ),
                  // 匿名モード: 右余白にタイムスタンプ
                  if (hideUserInfo)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 8),
                      child: Text(
                        _formatTimestamp(post.timestamp),
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ),
                ],
              ),

              // Engagement row
              SizedBox(height: compactEngagement ? 8 : 12),
              _buildEngagementRow(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRetweetHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: Row(
        children: [
          Icon(Icons.repeat, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${post.retweetedByUsername} がリツイート',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotedPostCard(BuildContext context, Post quoted) {
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
          // Quoted post header
          if (hideUserInfo)
            Row(
              children: [
                SnsBadge(service: quoted.source, size: 10),
                const SizedBox(width: 6),
                Text(
                  _formatTimestamp(quoted.timestamp),
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            )
          else
            Row(
              children: [
                quoted.avatarUrl != null
                    ? CachedNetworkImage(
                        imageUrl: quoted.avatarUrl!,
                        httpHeaders: kImageHeaders,
                        fadeInDuration: Duration.zero,
                        memCacheWidth: 40,
                        memCacheHeight: 40,
                        imageBuilder: (context, imageProvider) => CircleAvatar(
                          radius: 10,
                          backgroundImage: imageProvider,
                        ),
                        placeholder: (context, url) => const CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.grey,
                        ),
                        errorWidget: (context, url, error) => CircleAvatar(
                          radius: 10,
                          child: Text(
                            quoted.username.isNotEmpty
                                ? quoted.username[0].toUpperCase()
                                : '?',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      )
                    : CircleAvatar(
                        radius: 10,
                        child: Text(
                          quoted.username.isNotEmpty
                              ? quoted.username[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 10),
                        ),
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
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          if (quoted.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              quoted.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ],
          // Quoted post images
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

  Widget _buildAvatar(BuildContext context) {
    return GestureDetector(
      onTap: () => navigateToUserProfile(context, post: post),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Hero(
            tag: 'avatar_${post.id}',
            child: post.avatarUrl != null
                ? CachedNetworkImage(
                    imageUrl: post.avatarUrl!,
                    httpHeaders: kImageHeaders,
                    fadeInDuration: Duration.zero,
                    memCacheWidth: 80,
                    memCacheHeight: 80,
                    imageBuilder: (context, imageProvider) => CircleAvatar(
                      radius: 20,
                      backgroundImage: imageProvider,
                    ),
                    placeholder: (context, url) => const CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey,
                    ),
                    errorWidget: (context, url, error) => CircleAvatar(
                      radius: 20,
                      child: Text(
                        post.username.isNotEmpty
                            ? post.username[0].toUpperCase()
                            : '?',
                      ),
                    ),
                  )
                : CircleAvatar(
                    radius: 20,
                    child: Text(
                      post.username.isNotEmpty
                          ? post.username[0].toUpperCase()
                          : '?',
                    ),
                  ),
          ),
          Positioned(
            top: -4,
            left: -6,
            child: SnsBadge(service: post.source, size: 10),
          ),
        ],
      ),
    );
  }

  /// 取得元アバター（エンゲージメント行の左端、固定幅）
  Widget _buildSourceInfo() {
    if (hideUserInfo) return const SizedBox(width: 50);

    final ids = post.fetchedByAccountIds.toList();
    if (ids.isEmpty) return const SizedBox(width: 50);

    return SizedBox(
      width: 50,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ids.length <= 2)
            ...ids.map((id) => Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: _buildViaAvatar(id),
                ))
          else ...[
            _buildViaAvatar(ids[0]),
            const SizedBox(width: 2),
            _buildViaAvatar(ids[1]),
            Text(
              '+${ids.length - 2}',
              style: TextStyle(fontSize: 8, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNameRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  post.username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  post.handle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          _formatTimestamp(post.timestamp),
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildEngagementRow(BuildContext context) {
    final iconColor = Colors.grey[600];
    final compact = compactEngagement;
    final iconSize = compact ? 16.0 : 18.0;
    final fontSize = compact ? 11.0 : 12.0;

    return Row(
      children: [
        // SNSバッジ + 取得元アカウント（左端固定幅）
        _buildSourceInfo(),
        // Reply
        _EngagementButton(
          icon: Icons.chat_bubble_outline,
          count: post.replyCount,
          color: iconColor!,
          iconSize: iconSize,
          fontSize: fontSize,
          compact: compact,
          onTap: onReply,
        ),
        const Spacer(),
        // Repost
        _EngagementButton(
          icon: Icons.repeat,
          count: post.repostCount,
          color: iconColor,
          iconSize: iconSize,
          fontSize: fontSize,
          compact: compact,
          onTap: onRepost != null
              ? () => _showRepostMenu(context)
              : null,
          isActive: post.isReposted,
        ),
        const Spacer(),
        // Like
        _EngagementButton(
          icon: Icons.favorite_border,
          count: post.likeCount,
          color: iconColor,
          iconSize: iconSize,
          fontSize: fontSize,
          compact: compact,
          onTap: onLike,
          isActive: post.isLiked,
        ),
        const Spacer(),
        // Share
        GestureDetector(
          onTap: post.permalink != null
              ? () async {
                  final uri = Uri.tryParse(post.permalink!);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
              : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 4 : 8,
              vertical: compact ? 2 : 4,
            ),
            child: Icon(Icons.share_outlined, size: iconSize, color: iconColor),
          ),
        ),
      ],
    );
  }

  Widget _buildViaAvatar(String accountId) {
    final account = AccountStorageService.instance.getAccount(accountId);
    final url = account?.avatarUrl;
    if (url == null) {
      return const CircleAvatar(radius: 7, backgroundColor: Colors.grey);
    }
    return Opacity(
      opacity: 0.5,
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: kImageHeaders,
        fadeInDuration: Duration.zero,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: 7,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => const CircleAvatar(
          radius: 7,
          backgroundColor: Colors.grey,
        ),
        errorWidget: (context, url, error) => const CircleAvatar(
          radius: 7,
          backgroundColor: Colors.grey,
        ),
      ),
    );
  }
}

class _EngagementButton extends StatefulWidget {
  const _EngagementButton({
    required this.icon,
    required this.count,
    required this.color,
    required this.iconSize,
    required this.fontSize,
    this.onTap,
    this.isActive = false,
    this.compact = false,
  });

  final IconData icon;
  final int count;
  final Color color;
  final double iconSize;
  final double fontSize;
  final VoidCallback? onTap;
  final bool isActive;
  final bool compact;

  @override
  State<_EngagementButton> createState() => _EngagementButtonState();
}

class _EngagementButtonState extends State<_EngagementButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    _controller.forward(from: 0);
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: widget.onTap != null ? _handleTap : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 4 : 8,
          vertical: widget.compact ? 2 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) => Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
              child: Icon(widget.icon, size: widget.iconSize, color: widget.color),
            ),
            if (widget.count > 0) ...[
              const SizedBox(width: 4),
              Text(
                _formatCount(widget.count),
                style: TextStyle(color: widget.color, fontSize: widget.fontSize),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

/// Sensitive content overlay with tap-to-reveal behavior.
class _SensitiveOverlay extends StatefulWidget {
  const _SensitiveOverlay({
    required this.isSensitive,
    required this.child,
  });

  final bool isSensitive;
  final Widget child;

  @override
  State<_SensitiveOverlay> createState() => _SensitiveOverlayState();
}

class _SensitiveOverlayState extends State<_SensitiveOverlay> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.isSensitive || _revealed) {
      return widget.child;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          // Blurred content underneath
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: widget.child,
          ),
          // Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.visibility_off,
                      color: Colors.white70,
                      size: 28,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'センシティブな内容を含む可能性があります',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() => _revealed = true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                      ),
                      child: const Text('表示'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
