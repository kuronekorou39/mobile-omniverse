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
  static const _periodMs = 1500;

  // 再描画のきっかけにだけ使う。光の位置は時計から決めるので、
  // あとから出てきた棒も、画面上のほかの棒と同じ位置で光る
  late final _ticker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _periodMs),
  )..repeat();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = scheme.surfaceContainerLow;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return AnimatedBuilder(
      animation: _ticker,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        // 棒の色だけを塗り替える
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          // 帯は画面の幅を基準に流す。棒ごとに流すと、長い棒と短い棒で
          // 光り方がばらばらになって落ち着かない
          final box = context.findRenderObject() as RenderBox?;
          final left = box != null && box.attached && box.hasSize
              ? box.localToGlobal(Offset.zero).dx
              : 0.0;
          final t = (DateTime.now().millisecondsSinceEpoch % _periodMs) /
              _periodMs;
          return LinearGradient(
            colors: [base, highlight, base],
            stops: const [0.35, 0.5, 0.65],
            transform: _SlideGradient(screenWidth * (t * 2 - 1)),
          ).createShader(
              Rect.fromLTWH(-left, 0, screenWidth, bounds.height));
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

  /// 円（アバターなど）
  const SkeletonBox.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = size / 2;

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

/// 幅を親に対する割合で決める棒（本文の行など）
class _LineBox extends StatelessWidget {
  const _LineBox(this.widthFactor);

  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: const SkeletonBox(height: 12),
      );
}

/// 本文の行の長さ。全部同じだと作り物に見えるので、行ごとに変える
const _bodyLines = [
  [0.95, 0.6],
  [0.9, 0.95, 0.4],
  [0.75],
];

/// 投稿 1 件ぶんの読み込み表示。[PostCard] と同じ余白と並びにしてある
class PostSkeleton extends StatelessWidget {
  const PostSkeleton({super.key, this.separator = true, this.variant = 0});

  /// タイムラインの「区切り線」表示か（false ならカード表示）
  final bool separator;

  /// 本文の行数・長さを変える番号
  final int variant;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = _bodyLines[variant % _bodyLines.length];
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox.circle(size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              const Row(
                children: [
                  SkeletonBox(width: 88, height: 12),
                  SizedBox(width: 8),
                  SkeletonBox(width: 64, height: 12),
                ],
              ),
              for (final w in lines) ...[
                const SizedBox(height: 9),
                _LineBox(w),
              ],
              const SizedBox(height: 6),
            ],
          ),
        ),
      ],
    );

    if (separator) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: content,
          ),
          Divider(
              height: 1,
              thickness: 0.5,
              color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ],
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: content),
    );
  }
}

/// 通知 1 件ぶんの読み込み表示。左に種類のアイコン、右にアバターと本文
class NotificationSkeleton extends StatelessWidget {
  const NotificationSkeleton({super.key, this.variant = 0});

  final int variant;

  @override
  Widget build(BuildContext context) {
    final lines = _bodyLines[variant % _bodyLines.length];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 36,
            child: Center(child: SkeletonBox.circle(size: 24)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    SkeletonBox.circle(size: 36),
                    Spacer(),
                    SkeletonBox(width: 32, height: 10),
                  ],
                ),
                const SizedBox(height: 8),
                const SkeletonBox(width: 140, height: 12),
                for (final w in lines.take(2)) ...[
                  const SizedBox(height: 8),
                  _LineBox(w * 0.9),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ユーザー 1 人ぶんの読み込み表示（アバター + 名前 + @ID）
class UserTileSkeleton extends StatelessWidget {
  const UserTileSkeleton({super.key, this.variant = 0});

  final int variant;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const SkeletonBox.circle(size: 40),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 100.0 + (variant % 3) * 24, height: 12),
                const SizedBox(height: 8),
                SkeletonBox(width: 70.0 + (variant % 2) * 20, height: 10),
              ],
            ),
          ],
        ),
      );
}

/// 読み込み中の一覧。画面を埋める件数を並べ、スクロールはさせない
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, required this.itemBuilder, this.count = 8});

  final Widget Function(int index) itemBuilder;
  final int count;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [for (var i = 0; i < count; i++) itemBuilder(i)],
      );
}
