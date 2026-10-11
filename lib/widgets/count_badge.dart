import 'package:flutter/material.dart';

/// 未読件数のバッジ。
///
/// 数字が黙って入れ替わったり消えたりすると、変わったことに気づけない。
/// 出るとき・消えるときは伸び縮みし、数字が変わるときは下から差し替わる。
/// 0 のときも置いたままにして (見えないだけ)、消える動きを最後まで出す。
class CountBadge extends StatefulWidget {
  const CountBadge({super.key, required this.count});

  final int count;

  @override
  State<CountBadge> createState() => _CountBadgeState();
}

class _CountBadgeState extends State<CountBadge> {
  /// 表示する数字。0 になっても、消えきるまでは直前の数字を出しておく
  late int _shown = widget.count;

  @override
  void didUpdateWidget(covariant CountBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > 0) _shown = widget.count;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = widget.count > 0;
    final label = _shown >= 1000 ? '999+' : '$_shown';
    return IgnorePointer(
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: visible ? Curves.easeOutBack : Curves.easeIn,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: scheme.error,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.surface, width: 1.5),
          ),
          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
          child: ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 160),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.6),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  label,
                  key: ValueKey(label),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onError,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
