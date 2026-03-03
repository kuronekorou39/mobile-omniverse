import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/sns_service.dart';

class OverlayPostCard extends StatefulWidget {
  const OverlayPostCard({super.key, required this.post});

  final Post post;

  @override
  State<OverlayPostCard> createState() => _OverlayPostCardState();
}

class _OverlayPostCardState extends State<OverlayPostCard> {
  bool _isExpanded = false;

  Post get post => widget.post;

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${timestamp.month}/${timestamp.day}';
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }

  Color get _sourceColor => post.source == SnsService.x
      ? Colors.grey[600]!
      : const Color(0xFF0085FF);

  bool get _hasMedia =>
      post.imageUrls.isNotEmpty || post.videoThumbnailUrl != null;

  String? get _thumbnailUrl {
    if (post.imageUrls.isNotEmpty) return post.imageUrls.first;
    return post.videoThumbnailUrl;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // RT indicator
            if (post.isRetweet && post.retweetedByHandle != null)
              Padding(
                padding: const EdgeInsets.only(left: 28, bottom: 1),
                child: Text(
                  '↻ ${post.retweetedByHandle} がリポスト',
                  style: const TextStyle(fontSize: 8, color: Colors.white30),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Main content row
            _isExpanded ? _buildExpanded() : _buildCollapsed(),

            // Divider
            Divider(height: 6, thickness: 0.3, color: Colors.grey[800]),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsed() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: _buildAvatar(12),
        ),
        const SizedBox(width: 4),
        // Text content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Body text (2 lines)
              Text(
                post.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
              // Quoted post (1 line)
              if (post.quotedPost != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    '↩ ${post.quotedPost!.handle}: ${post.quotedPost!.body}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: Colors.white38),
                  ),
                ),
              // Meta line
              const SizedBox(height: 1),
              _buildMetaLine(),
            ],
          ),
        ),
        // Media thumbnail
        if (_hasMedia)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _buildThumbnail(28),
          ),
      ],
    );
  }

  Widget _buildExpanded() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: _buildAvatar(12),
        ),
        const SizedBox(width: 4),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Username
              Text(
                post.username,
                style: const TextStyle(fontSize: 10, color: Colors.white60),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              // Full body text
              Text(
                post.body,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
              // Media (full width)
              if (_hasMedia)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _buildExpandedMedia(),
                ),
              // Quoted post (full)
              if (post.quotedPost != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _buildExpandedQuote(),
                ),
              // Meta line
              const SizedBox(height: 3),
              _buildMetaLine(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _sourceColor,
      backgroundImage:
          post.avatarUrl != null ? NetworkImage(post.avatarUrl!) : null,
      onBackgroundImageError: post.avatarUrl != null ? (_, __) {} : null,
      child: post.avatarUrl == null
          ? Text(
              post.username.isNotEmpty
                  ? post.username[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.8,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }

  Widget _buildThumbnail(double size) {
    final url = _thumbnailUrl;
    if (url == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey[800],
                child: const Icon(Icons.image, size: 14, color: Colors.white24),
              ),
            ),
            if (post.videoUrl != null || post.videoThumbnailUrl != null)
              const Center(
                child: Icon(Icons.play_circle_outline,
                    size: 16, color: Colors.white70),
              ),
            if (post.imageUrls.length > 1)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '${post.imageUrls.length}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedMedia() {
    final url = _thumbnailUrl;
    if (url == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 120),
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 60,
                  color: Colors.grey[800],
                  child: const Center(
                    child:
                        Icon(Icons.broken_image, size: 20, color: Colors.white24),
                  ),
                ),
              ),
            ),
            if (post.videoUrl != null || post.videoThumbnailUrl != null)
              const Positioned.fill(
                child: Center(
                  child: Icon(Icons.play_circle_outline,
                      size: 32, color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedQuote() {
    final q = post.quotedPost!;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q.handle,
            style: const TextStyle(fontSize: 8, color: Colors.white38),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            q.body,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white54,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaLine() {
    const metaStyle = TextStyle(fontSize: 8, color: Colors.white24);
    return Row(
      children: [
        // Handle (left)
        Expanded(
          child: Text(
            post.handle,
            style: const TextStyle(fontSize: 8, color: Colors.white30),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Engagement (right-aligned)
        const Icon(Icons.favorite_border, size: 9, color: Colors.white24),
        const SizedBox(width: 2),
        Text(_formatCount(post.likeCount), style: metaStyle),
        const SizedBox(width: 6),
        const Icon(Icons.repeat, size: 9, color: Colors.white24),
        const SizedBox(width: 2),
        Text(_formatCount(post.repostCount), style: metaStyle),
        const SizedBox(width: 6),
        // Timestamp (far right)
        Text(_formatTimestamp(post.timestamp), style: metaStyle),
      ],
    );
  }
}
