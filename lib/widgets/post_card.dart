import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/post.dart';
import '../screens/user_profile_screen.dart';
import '../utils/image_headers.dart';
import 'post_media.dart';
import 'sns_badge.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    this.accountHandle,
    this.onTap,
    this.onLike,
    this.onRepost,
  });

  final Post post;
  final String? accountHandle;
  final VoidCallback? onTap;
  final VoidCallback? onLike;
  final VoidCallback? onRepost;

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${timestamp.month}/${timestamp.day}';
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
              if (post.isRetweet && post.retweetedByUsername != null) ...[
                _buildRetweetHeader(context),
                const SizedBox(height: 6),
              ],

              // Header row
              _buildHeader(context, accountHandle),
              const SizedBox(height: 8),

              // Body text with tappable links
              if (post.body.isNotEmpty) LinkedText(text: post.body),

              // Images
              if (post.imageUrls.isNotEmpty) ...[
                const SizedBox(height: 8),
                PostImageGrid(imageUrls: post.imageUrls),
              ],

              // Video thumbnail
              if (post.videoUrl != null && post.videoThumbnailUrl != null) ...[
                const SizedBox(height: 8),
                PostVideoThumbnail(
                  videoUrl: post.videoUrl!,
                  thumbnailUrl: post.videoThumbnailUrl!,
                ),
              ],

              // Quoted post card
              if (post.quotedPost != null) ...[
                const SizedBox(height: 8),
                _buildQuotedPostCard(context, post.quotedPost!),
              ],

              // Engagement row
              const SizedBox(height: 8),
              _buildEngagementRow(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRetweetHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 28),
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
          Row(
            children: [
              quoted.avatarUrl != null
                  ? CachedNetworkImage(
                      imageUrl: quoted.avatarUrl!,
                      httpHeaders: kImageHeaders,
                      imageBuilder: (context, imageProvider) => CircleAvatar(
                        radius: 10,
                        backgroundImage: imageProvider,
                      ),
                      placeholder: (context, url) => CircleAvatar(
                        radius: 10,
                        child: Text(
                          quoted.username.isNotEmpty
                              ? quoted.username[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 10),
                        ),
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

  Widget _buildHeader(BuildContext context, String? accountHandle) {
    return Row(
      children: [
        // Avatar (タップでプロフィール画面へ)
        GestureDetector(
          onTap: () => navigateToUserProfile(context, post: post),
          child: Hero(
          tag: 'avatar_${post.id}',
          child: post.avatarUrl != null
              ? CachedNetworkImage(
                  imageUrl: post.avatarUrl!,
                  httpHeaders: kImageHeaders,
                  imageBuilder: (context, imageProvider) => CircleAvatar(
                    radius: 20,
                    backgroundImage: imageProvider,
                  ),
                  placeholder: (context, url) => CircleAvatar(
                    radius: 20,
                    child: Text(
                      post.username.isNotEmpty
                          ? post.username[0].toUpperCase()
                          : '?',
                    ),
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
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      post.username,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SnsBadge(service: post.source),
                ],
              ),
              Row(
                children: [
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
                  if (accountHandle != null) ...[
                    Text(
                      ' via ',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        accountHandle,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Text(
          _formatTimestamp(post.timestamp),
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildEngagementRow(BuildContext context) {
    final iconColor = Colors.grey[600];
    const iconSize = 18.0;
    const fontSize = 12.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Reply
        _EngagementButton(
          icon: Icons.chat_bubble_outline,
          count: post.replyCount,
          color: iconColor!,
          iconSize: iconSize,
          fontSize: fontSize,
        ),
        // Repost
        _EngagementButton(
          icon: Icons.repeat,
          count: post.repostCount,
          color: post.isReposted ? Colors.green : iconColor,
          iconSize: iconSize,
          fontSize: fontSize,
          onTap: onRepost,
          isActive: post.isReposted,
        ),
        // Like
        _EngagementButton(
          icon: post.isLiked ? Icons.favorite : Icons.favorite_border,
          count: post.likeCount,
          color: post.isLiked ? Colors.red : iconColor,
          iconSize: iconSize,
          fontSize: fontSize,
          onTap: onLike,
          isActive: post.isLiked,
        ),
        // Share
        IconButton(
          icon: Icon(Icons.share_outlined, size: iconSize, color: iconColor),
          onPressed: post.permalink != null
              ? () async {
                  final uri = Uri.tryParse(post.permalink!);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
              : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
        ),
      ],
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
  });

  final IconData icon;
  final int count;
  final Color color;
  final double iconSize;
  final double fontSize;
  final VoidCallback? onTap;
  final bool isActive;

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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
