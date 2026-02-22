import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/post.dart';
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
              CircleAvatar(
                radius: 10,
                backgroundImage: quoted.avatarUrl != null
                    ? CachedNetworkImageProvider(quoted.avatarUrl!)
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
        // Avatar
        Hero(
          tag: 'avatar_${post.id}',
          child: CircleAvatar(
            radius: 20,
            backgroundImage: post.avatarUrl != null
                ? CachedNetworkImageProvider(post.avatarUrl!)
                : null,
            child: post.avatarUrl == null
                ? Text(
                    post.username.isNotEmpty
                        ? post.username[0].toUpperCase()
                        : '?',
                  )
                : null,
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

class _EngagementButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: color),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                _formatCount(count),
                style: TextStyle(color: color, fontSize: fontSize),
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
