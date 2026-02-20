import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'image_viewer.dart';

/// 投稿本文のリンク付きテキストを構築する共有ウィジェット
class LinkedText extends StatelessWidget {
  const LinkedText({
    super.key,
    required this.text,
    this.style,
    this.selectable = false,
  });

  final String text;
  final TextStyle? style;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final urlRegex = RegExp(r'https?://[^\s]+');
    final matches = urlRegex.allMatches(text).toList();

    if (matches.isEmpty) {
      if (selectable) {
        return SelectableText(
          text,
          style: style ?? Theme.of(context).textTheme.bodyMedium,
        );
      }
      return Text(text, style: style ?? Theme.of(context).textTheme.bodyMedium);
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;
    final baseStyle = style ?? Theme.of(context).textTheme.bodyMedium;

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
              style: baseStyle?.copyWith(
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
      TextSpan(style: baseStyle, children: spans),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 画像グリッド表示の共有ウィジェット
class PostImageGrid extends StatelessWidget {
  const PostImageGrid({super.key, required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    final count = imageUrls.length.clamp(0, 4);
    if (count == 0) return const SizedBox.shrink();

    if (count == 1) return _buildSingleImage(context, imageUrls[0], 0);

    if (count == 2) {
      return Row(
        children: [
          Expanded(child: _buildGridImage(context, imageUrls[0], 0,
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8)))),
          const SizedBox(width: 2),
          Expanded(child: _buildGridImage(context, imageUrls[1], 1,
              borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8)))),
        ],
      );
    }

    if (count == 3) {
      return Row(
        children: [
          Expanded(
            child: _buildGridImage(context, imageUrls[0], 0,
                height: 200,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8))),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              children: [
                _buildGridImage(context, imageUrls[1], 1,
                    height: 99,
                    borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8))),
                const SizedBox(height: 2),
                _buildGridImage(context, imageUrls[2], 2,
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
            Expanded(child: _buildGridImage(context, imageUrls[0], 0,
                height: 100,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8)))),
            const SizedBox(width: 2),
            Expanded(child: _buildGridImage(context, imageUrls[1], 1,
                height: 100,
                borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8)))),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(child: _buildGridImage(context, imageUrls[2], 2,
                height: 100,
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8)))),
            const SizedBox(width: 2),
            Expanded(child: _buildGridImage(context, imageUrls[3], 3,
                height: 100,
                borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(8)))),
          ],
        ),
      ],
    );
  }

  Widget _buildSingleImage(BuildContext context, String url, int index) {
    return GestureDetector(
      onTap: () => _openViewer(context, index),
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
              child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
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
      onTap: () => _openViewer(context, index),
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

  void _openViewer(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewer(
          imageUrls: imageUrls,
          initialIndex: index,
        ),
      ),
    );
  }
}

/// 動画サムネイル表示の共有ウィジェット
class PostVideoThumbnail extends StatelessWidget {
  const PostVideoThumbnail({
    super.key,
    required this.videoUrl,
    required this.thumbnailUrl,
  });

  final String videoUrl;
  final String thumbnailUrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(videoUrl);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CachedNetworkImage(
              imageUrl: thumbnailUrl,
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
                child: const Icon(Icons.videocam,
                    color: Colors.white54, size: 48),
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
}
