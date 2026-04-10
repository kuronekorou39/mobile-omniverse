import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../utils/image_headers.dart';

/// Full-screen image viewer with swipe-to-dismiss
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late PageController _pageController;
  late int _currentIndex;
  final List<_ZoomState> _zoomStates = [];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _zoomStates.addAll(
      List.generate(widget.imageUrls.length, (_) => _ZoomState()),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 現在のページのズーム率が120%超ならスワイプ無効
    final blockSwipe = _zoomStates[_currentIndex].scale > 1.2;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: widget.imageUrls.length > 1
            ? Text(
                '${_currentIndex + 1} / ${widget.imageUrls.length}',
                style: const TextStyle(color: Colors.white),
              )
            : null,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageUrls.length,
        physics: blockSwipe
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return _ZoomableImage(
            imageUrl: widget.imageUrls[index],
            zoomState: _zoomStates[index],
            onScaleChanged: () {
              if (index == _currentIndex) setState(() {});
            },
          );
        },
      ),
    );
  }
}

class _ZoomState {
  double scale = 1.0;
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.imageUrl,
    required this.zoomState,
    required this.onScaleChanged,
  });

  final String imageUrl;
  final _ZoomState zoomState;
  final VoidCallback onScaleChanged;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _animation;

  static const double _doubleTapScale = 2.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _controller.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _controller.value.getMaxScaleOnAxis();
    if ((scale - widget.zoomState.scale).abs() > 0.01) {
      widget.zoomState.scale = scale;
      widget.onScaleChanged();
    }
  }

  void _onDoubleTap(TapDownDetails details) {
    final currentScale = _controller.value.getMaxScaleOnAxis();

    final Matrix4 target;
    if (currentScale > 1.05) {
      // 100%より大きい → 100%に戻す
      target = Matrix4.identity();
    } else {
      // 100%以下 → 拡大（タップ位置を中心に）
      final position = details.localPosition;
      final x = -position.dx * (_doubleTapScale - 1);
      final y = -position.dy * (_doubleTapScale - 1);
      target = Matrix4.identity()
        ..translate(x, y)
        ..scale(_doubleTapScale);
    }

    _animation = Matrix4Tween(
      begin: _controller.value,
      end: target,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _animController.forward(from: 0).then((_) {
      _controller.value = target;
    });

    _animController.addListener(() {
      if (_animation != null) {
        _controller.value = _animation!.value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Offset? doubleTapPosition;

    return GestureDetector(
      onDoubleTapDown: (details) => doubleTapPosition = details.localPosition,
      onDoubleTap: () {
        if (doubleTapPosition != null) {
          _onDoubleTap(TapDownDetails(localPosition: doubleTapPosition!));
        }
      },
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 0.5,
        maxScale: 5.0,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            httpHeaders: kImageHeaders,
            fit: BoxFit.contain,
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (context, error, stackTrace) =>
                const Icon(Icons.broken_image, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}
