import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/post.dart';
import '../services/account_storage_service.dart';
import 'image_viewer.dart';
import 'sns_badge.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onLike,
    this.onRepost,
  });

  final Post post;
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

    // Fetch account handle for display
    String? accountHandle;
    if (post.accountId != null) {
      final account =
          AccountStorageService.instance.getAccount(post.accountId!);
      if (account != null) accountHandle = account.handle;
    }

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
              // Header row
              _buildHeader(context, accountHandle),
              const SizedBox(height: 8),

              // Body text with tappable links
              _buildBody(context),

              // Images
              if (post.imageUrls.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildImageGrid(context),
              ],

              // Video thumbnail
              if (post.videoUrl != null && post.videoThumbnailUrl != null) ...[
                const SizedBox(height: 8),
                _buildVideoThumbnail(context),
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

  Widget _buildBody(BuildContext context) {
    final text = post.body;
    if (text.isEmpty) return const SizedBox.shrink();

    // Parse URLs in text for tappable links
    final urlRegex = RegExp(r'https?://[^\s]+');
    final matches = urlRegex.allMatches(text).toList();

    if (matches.isEmpty) {
      return SelectableText(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    // Build rich text with tappable links
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(
        WidgetSpan(
          child: GestureDetector(
            onTap: () => _launchUrl(url),
            child: Text(
              url,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: spans,
      ),
    );
  }

  Widget _buildImageGrid(BuildContext context) {
    final images = post.imageUrls;
    final count = images.length.clamp(0, 4);

    if (count == 1) {
      return _buildSingleImage(context, images[0], 0);
    }

    if (count == 2) {
      return Row(
        children: [
          Expanded(child: _buildGridImage(context, images[0], 0, borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)))),
          const SizedBox(width: 2),
          Expanded(child: _buildGridImage(context, images[1], 1, borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)))),
        ],
      );
    }

    if (count == 3) {
      return Row(
        children: [
          Expanded(
            child: _buildGridImage(context, images[0], 0,
                height: 200,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8))),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              children: [
                _buildGridImage(context, images[1], 1,
                    height: 99,
                    borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8))),
                const SizedBox(height: 2),
                _buildGridImage(context, images[2], 2,
                    height: 99,
                    borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(8))),
              ],
            ),
          ),
        ],
      );
    }

    // 4 images
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildGridImage(context, images[0], 0, height: 100, borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)))),
            const SizedBox(width: 2),
            Expanded(child: _buildGridImage(context, images[1], 1, height: 100, borderRadius: const BorderRadius.only(topRight: Radius.circular(8)))),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(child: _buildGridImage(context, images[2], 2, height: 100, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)))),
            const SizedBox(width: 2),
            Expanded(child: _buildGridImage(context, images[3], 3, height: 100, borderRadius: const BorderRadius.only(bottomRight: Radius.circular(8)))),
          ],
        ),
      ],
    );
  }

  Widget _buildSingleImage(BuildContext context, String url, int index) {
    return GestureDetector(
      onTap: () => _openImageViewer(context, index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (context, url) => Container(
              height: 200,
              color: Colors.grey[300],
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (context, error, stackTrace) => Container(
              height: 100,
              color: Colors.grey[300],
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridImage(
    BuildContext context,
    String url,
    int index, {
    double? height,
    BorderRadius? borderRadius,
  }) {
    return GestureDetector(
      onTap: () => _openImageViewer(context, index),
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          height: height ?? 150,
          width: double.infinity,
          placeholder: (context, url) => Container(
            height: height ?? 150,
            color: Colors.grey[300],
          ),
          errorWidget: (context, error, stackTrace) => Container(
            height: height ?? 150,
            color: Colors.grey[300],
            child: const Icon(Icons.broken_image, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail(BuildContext context) {
    return GestureDetector(
      onTap: () => _launchUrl(post.videoUrl!),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CachedNetworkImage(
              imageUrl: post.videoThumbnailUrl!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 200,
              placeholder: (context, url) => Container(
                height: 200,
                color: Colors.grey[300],
              ),
              errorWidget: (context, error, stackTrace) => Container(
                height: 200,
                color: Colors.grey[800],
                child: const Icon(Icons.videocam, color: Colors.white54, size: 48),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
          ],
        ),
      ),
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
              ? () => _launchUrl(post.permalink!)
              : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  void _openImageViewer(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewer(
          imageUrls: post.imageUrls,
          initialIndex: index,
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
