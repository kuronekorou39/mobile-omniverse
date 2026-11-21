import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/settings_provider.dart' show ImagePreviewSize;
import '../utils/image_headers.dart';
import '../utils/open_link.dart';
import 'image_viewer.dart';

/// 画像 1 枚の高さが画面の高さに占める上限。
/// 縦長の画像を「大」で出しても 1 画面に収まり、前後の投稿が見えるようにする。
const _maxScreenHeightFraction = 0.8;

/// デコード幅の候補。スマホは 720 で足りるが、iPad の全幅では粗く見えるので上げる
const _memCacheWidthPhone = 720;
const _memCacheWidthTablet = 1440;

int _memCacheWidthFor(BuildContext context, double layoutWidth) {
  final physical = layoutWidth * MediaQuery.devicePixelRatioOf(context);
  return physical > 1080 ? _memCacheWidthTablet : _memCacheWidthPhone;
}

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
            // 誤タップでいきなり外へ飛ばないよう、行き先を見せてから開く
            onTap: () => confirmAndOpenUrl(context, url),
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

}

/// 画像グリッド表示の共有ウィジェット
class PostImageGrid extends StatelessWidget {
  const PostImageGrid({
    super.key,
    required this.imageUrls,
    this.previewSize = ImagePreviewSize.medium,
    this.threadImageUrls,
    this.threadIndexOffset = 0,
  });

  final List<String> imageUrls;

  /// 高さの決め方。置かれた幅に対する比率で決まる
  final ImagePreviewSize previewSize;
  /// スレッド全体の画像URLリスト（指定時はビューアでこちらを使用）
  final List<String>? threadImageUrls;
  /// threadImageUrls 内でのこの投稿の画像の開始位置
  final int threadIndexOffset;

  @override
  Widget build(BuildContext context) {
    final count = imageUrls.length.clamp(0, 4);
    if (count == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildForWidth(context, count, constraints.maxWidth),
    );
  }

  Widget _buildForWidth(BuildContext context, int count, double width) {
    if (count == 1) return _buildSingleImage(context, imageUrls[0], 0, width);

    final gh = width * previewSize.gridImageHeightRatio;

    if (count == 2) {
      return Row(
        children: [
          Expanded(child: _buildGridImage(context, imageUrls[0], 0,
              height: gh,
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8)))),
          const SizedBox(width: 2),
          Expanded(child: _buildGridImage(context, imageUrls[1], 1,
              height: gh,
              borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8)))),
        ],
      );
    }

    if (count == 3) {
      final tallH = gh * 2 + 2;
      final smallH = gh;
      return Row(
        children: [
          Expanded(
            child: _buildGridImage(context, imageUrls[0], 0,
                height: tallH,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8))),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              children: [
                _buildGridImage(context, imageUrls[1], 1,
                    height: smallH,
                    borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(8))),
                const SizedBox(height: 2),
                _buildGridImage(context, imageUrls[2], 2,
                    height: smallH,
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
                height: gh,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8)))),
            const SizedBox(width: 2),
            Expanded(child: _buildGridImage(context, imageUrls[1], 1,
                height: gh,
                borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8)))),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(child: _buildGridImage(context, imageUrls[2], 2,
                height: gh,
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8)))),
            const SizedBox(width: 2),
            Expanded(child: _buildGridImage(context, imageUrls[3], 3,
                height: gh,
                // X は 1 投稿に 20 枚まで載る。並べるのは 4 枚までで、残りは数で示す
                hiddenCount: imageUrls.length - 4,
                borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(8)))),
          ],
        ),
      ],
    );
  }

  Widget _buildSingleImage(
      BuildContext context, String url, int index, double width) {
    final byWidth = width * previewSize.singleImageHeightRatio;
    final byScreen =
        MediaQuery.sizeOf(context).height * _maxScreenHeightFraction;
    return GestureDetector(
      onTap: () => _openViewer(context, index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: byWidth < byScreen ? byWidth : byScreen),
          child: CachedNetworkImage(
            imageUrl: url,
            httpHeaders: kImageHeaders,
            fadeInDuration: Duration.zero,
            memCacheWidth: _memCacheWidthFor(context, width),
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (context, url) => Container(
              height: 200,
              color: Colors.grey[300],
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
    required double height,
    BorderRadius? borderRadius,
    int hiddenCount = 0,
  }) {
    final image = CachedNetworkImage(
      imageUrl: url,
      httpHeaders: kImageHeaders,
      fadeInDuration: Duration.zero,
      memCacheWidth: 360,
      fit: BoxFit.cover,
      height: height,
      width: double.infinity,
      placeholder: (context, url) => Container(
        height: height,
        color: Colors.grey[300],
      ),
      errorWidget: (context, error, stackTrace) => Container(
        height: height,
        color: Colors.grey[300],
        child: const Icon(Icons.broken_image, size: 20),
      ),
    );
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _openViewer(context, index),
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: hiddenCount <= 0
            ? image
            : Stack(
                children: [
                  image,
                  Positioned.fill(
                    child: ColoredBox(
                      color: scheme.inverseSurface.withValues(alpha: 0.55),
                      child: Center(
                        child: Text(
                          '+$hiddenCount',
                          style: TextStyle(
                            color: scheme.onInverseSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _openViewer(BuildContext context, int index) {
    final viewerUrls = threadImageUrls ?? imageUrls;
    final viewerIndex = threadImageUrls != null ? threadIndexOffset + index : index;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => ImageViewer(
          imageUrls: viewerUrls,
          initialIndex: viewerIndex,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
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
    this.previewSize = ImagePreviewSize.medium,
  });

  final String videoUrl;
  final String thumbnailUrl;

  /// 高さの決め方。置かれた幅に対する比率で決まる
  final ImagePreviewSize previewSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildForWidth(context, constraints.maxWidth),
    );
  }

  Widget _buildForWidth(BuildContext context, double width) {
    final height = width * previewSize.videoHeightRatio;
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
              httpHeaders: kImageHeaders,
              fadeInDuration: Duration.zero,
              memCacheWidth: _memCacheWidthFor(context, width),
              fit: BoxFit.cover,
              width: double.infinity,
              height: height,
              placeholder: (context, url) => Container(
                height: height,
                color: Colors.grey[300],
              ),
              errorWidget: (context, error, stackTrace) => Container(
                height: height,
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
