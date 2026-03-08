import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/sns_service.dart';

/// オーバーレイ用テーマカラーセット
class OverlayThemeColors {
  const OverlayThemeColors({
    required this.bg,
    required this.headerBg,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.textQuaternary,
    required this.divider,
    required this.border,
    required this.iconColor,
  });

  final Color bg;
  final Color headerBg;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color textQuaternary;
  final Color divider;
  final Color border;
  final Color iconColor;

  static const dark = OverlayThemeColors(
    bg: Color(0xFF1C1C1E),
    headerBg: Color(0xFF2C2C2E),
    text: Colors.white70,
    textSecondary: Colors.white60,
    textTertiary: Colors.white54,
    textQuaternary: Colors.white38,
    divider: Color(0xFF3A3A3C),
    border: Color(0xFF48484A),
    iconColor: Colors.white24,
  );

  static const light = OverlayThemeColors(
    bg: Color(0xFFF5F5F5),
    headerBg: Color(0xFFE8E8E8),
    text: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF3A3A3C),
    textTertiary: Color(0xFF636366),
    textQuaternary: Color(0xFF8E8E93),
    divider: Color(0xFFD1D1D6),
    border: Color(0xFFC7C7CC),
    iconColor: Color(0xFFAEAEB2),
  );
}

class OverlayPostCard extends StatefulWidget {
  const OverlayPostCard({
    super.key,
    required this.post,
    this.onShowDetail,
    this.fontSize = 10,
    this.theme = OverlayThemeColors.dark,
    this.isExpanded = false,
    this.onToggleExpand,
  });

  final Post post;
  final VoidCallback? onShowDetail;
  final double fontSize;
  final OverlayThemeColors theme;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;

  @override
  State<OverlayPostCard> createState() => _OverlayPostCardState();
}

class _OverlayPostCardState extends State<OverlayPostCard> {

  Post get post => widget.post;
  OverlayThemeColors get t => widget.theme;

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

  double get _fs => widget.fontSize;

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
      onTap: widget.onToggleExpand,
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
                  style: TextStyle(fontSize: _fs - 2, color: t.textQuaternary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Main content row
            widget.isExpanded ? _buildExpanded() : _buildCollapsed(),

            // Divider
            Divider(height: 6, thickness: 0.3, color: t.divider),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Body + thumbnail row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: _buildAvatar(12),
            ),
            const SizedBox(width: 4),
            // Body text (3 lines)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.text,
                      fontSize: _fs,
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
                        style: TextStyle(
                            fontSize: _fs - 1, color: t.textQuaternary),
                      ),
                    ),
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
        ),
        // Meta line (always full width)
        Padding(
          padding: const EdgeInsets.only(left: 28, top: 1),
          child: _buildMetaLine(),
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
                style: TextStyle(fontSize: _fs, color: t.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              // Full body text
              Text(
                post.body,
                style: TextStyle(
                  color: t.text,
                  fontSize: _fs,
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
              // Show detail button
              if (widget.onShowDetail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: GestureDetector(
                    onTap: widget.onShowDetail,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: t.border, width: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '詳細を表示',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: t.textTertiary,
                          fontSize: _fs - 1,
                        ),
                      ),
                    ),
                  ),
                ),
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
                child: Icon(Icons.image, size: 14, color: t.iconColor),
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
                  child: Center(
                    child:
                        Icon(Icons.broken_image, size: 20, color: t.iconColor),
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
        border: Border.all(color: t.border.withAlpha(80)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q.handle,
            style: TextStyle(fontSize: _fs - 2, color: t.textQuaternary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            q.body,
            style: TextStyle(
              fontSize: _fs - 1,
              color: t.textTertiary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaLine() {
    final metaStyle = TextStyle(fontSize: _fs - 2, color: t.iconColor);
    return Row(
      children: [
        // Handle (left)
        Expanded(
          child: Text(
            post.handle,
            style: TextStyle(fontSize: _fs - 2, color: t.textQuaternary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Engagement (right-aligned)
        Icon(Icons.favorite_border, size: 9, color: t.iconColor),
        const SizedBox(width: 2),
        Text(_formatCount(post.likeCount), style: metaStyle),
        const SizedBox(width: 6),
        Icon(Icons.repeat, size: 9, color: t.iconColor),
        const SizedBox(width: 2),
        Text(_formatCount(post.repostCount), style: metaStyle),
        const SizedBox(width: 6),
        // Timestamp (far right)
        Text(_formatTimestamp(post.timestamp), style: metaStyle),
      ],
    );
  }
}
