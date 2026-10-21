import 'package:flutter/material.dart';

/// 読み込み中に、値の入る場所だけを薄い棒で示す。
///
/// 回るインジケーターに置き換えると、読み込みの前後で画面の形が大きく
/// 変わって落ち着かない。見出しやボタンなど決まっている部分はそのまま出し、
/// まだ分からない値だけを [SkeletonBox] にする。
///
/// 子の不透明な部分をすべて光の帯で塗るので、文字を含むものは包まないこと
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = scheme.surfaceContainerLow;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        // 棒の色だけを塗り替える。文字や他の部品はそのまま
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          // 帯が画面の左外から右外まで流れるように、幅の 3 倍を動かす
          final dx = bounds.width * (_controller.value * 3 - 1.5);
          return LinearGradient(
            colors: [base, highlight, base],
            stops: const [0.35, 0.5, 0.65],
            transform: _SlideGradient(dx),
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);

  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// 値の代わりに置く棒。単体でも光る
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Shimmer(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
}
