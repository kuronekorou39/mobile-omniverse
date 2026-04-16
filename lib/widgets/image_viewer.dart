import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_snackbar.dart';
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

  // スワイプで閉じる用
  double _dragOffsetY = 0;
  double _dragOffsetX = 0;
  double _bgOpacity = 1.0;
  bool _isDragging = false;
  bool _edgeDismissing = false;

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

  int get _scalePercent {
    final raw = _zoomStates[_currentIndex].scale * 100;
    if ((raw - 100).abs() < 3) return 100;
    if ((raw - 200).abs() < 3) return 200;
    return (raw / 5).round() * 5;
  }
  bool get _isZoomed => _zoomStates[_currentIndex].scale > 1.05;

  Future<void> _downloadImage() async {
    final url = widget.imageUrls[_currentIndex];
    try {
      final file = await DefaultCacheManager().getSingleFile(url, headers: kImageHeaders);
      final prefs = await SharedPreferences.getInstance();
      final saveFolder = prefs.getString('settings_image_save_folder') ?? 'Pictures/OmniVerse';
      final Directory picDir;
      if (Platform.isIOS) {
        final docDir = await getApplicationDocumentsDirectory();
        picDir = Directory('${docDir.path}/$saveFolder');
      } else {
        final dir = await getExternalStorageDirectory();
        if (dir == null) throw Exception('ストレージにアクセスできません');
        picDir = Directory('${dir.parent.parent.parent.parent.path}/$saveFolder');
      }
      if (!await picDir.exists()) await picDir.create(recursive: true);
      final ext = url.contains('.png') ? 'png' : 'jpg';
      final name = 'omni_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final savePath = '${picDir.path}/$name';
      await file.copy(savePath);
      if (mounted) {
        showAppSnackBar(
          context,
          '保存しました: $saveFolder/$name',
          type: SnackType.success,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: '開く',
            onPressed: () => OpenFilex.open(savePath),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, '保存に失敗しました: $e', type: SnackType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final blockSwipe = _zoomStates[_currentIndex].scale > 1.2;
    final scale = _scalePercent;

    final singleImage = widget.imageUrls.length == 1;

    return GestureDetector(
      // 縦スワイプで閉じる（100%時のみ）
      onVerticalDragStart: _isZoomed ? null : (_) {
        _isDragging = true;
      },
      onVerticalDragUpdate: _isZoomed ? null : (details) {
        if (!_isDragging) return;
        setState(() {
          _dragOffsetY += details.delta.dy;
          final distance = _dragOffsetY.abs() + _dragOffsetX.abs();
          _bgOpacity = (1.0 - (distance / 300)).clamp(0.0, 1.0);
        });
      },
      onVerticalDragEnd: _isZoomed ? null : (details) {
        _isDragging = false;
        final velocity = details.primaryVelocity?.abs() ?? 0;
        if (_dragOffsetY.abs() > 50 || velocity > 800) {
          Navigator.of(context).pop();
        } else {
          setState(() {
            _dragOffsetY = 0;
            _bgOpacity = 1.0;
          });
        }
      },
      // 1枚の時: 横スワイプでも閉じる
      onHorizontalDragUpdate: (!_isZoomed && singleImage) ? (details) {
        setState(() {
          _dragOffsetX += details.delta.dx;
          _bgOpacity = (1.0 - (_dragOffsetX.abs() / 300)).clamp(0.0, 1.0);
        });
      } : null,
      onHorizontalDragEnd: (!_isZoomed && singleImage) ? (details) {
        final velocity = details.primaryVelocity?.abs() ?? 0;
        if (_dragOffsetX.abs() > 50 || velocity > 800) {
          Navigator.of(context).pop();
        } else {
          setState(() {
            _dragOffsetX = 0;
            _bgOpacity = 1.0;
          });
        }
      } : null,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: _bgOpacity),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.imageUrls.length > 1) ...[
                Text(
                  '${_currentIndex + 1}/${widget.imageUrls.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(width: 12),
              ],
              Text(
                '$scale%',
                style: TextStyle(
                  color: scale == 100 ? Colors.white54 : Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.download, size: 22),
              tooltip: 'ダウンロード',
              onPressed: _downloadImage,
            ),
          ],
        ),
        body: Transform.translate(
          offset: Offset(_dragOffsetX, _dragOffsetY),
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              if (_isZoomed || _edgeDismissing) return false;
              final metrics = notification.metrics;
              final isAtStart = _currentIndex == 0;
              final isAtEnd = _currentIndex == widget.imageUrls.length - 1;
              // 終端でのオーバースクロールを検知
              if (isAtStart && metrics.pixels < -10) {
                _edgeDismissing = true;
                Navigator.of(context).pop();
                return true;
              }
              if (isAtEnd && metrics.pixels > metrics.maxScrollExtent + 10) {
                _edgeDismissing = true;
                Navigator.of(context).pop();
                return true;
              }
              return false;
            },
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              physics: blockSwipe
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
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
          ),
        ),
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
      target = Matrix4.identity();
    } else {
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
