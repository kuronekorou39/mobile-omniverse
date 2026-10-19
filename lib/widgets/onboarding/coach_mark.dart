import 'dart:async';

import 'package:flutter/material.dart';

/// 画面の一部だけを明るく残し、その横に説明を出す案内。
///
/// どこをタップしても閉じる。明るい部分をタップしたときは [onTargetTap] も呼ぶ
/// （「ここを押してね」と言われた場所を押したら、そのまま進めるように）。
Future<void> showCoachMark(
  BuildContext context, {
  required GlobalKey targetKey,
  required String title,
  required String message,
  VoidCallback? onTargetTap,
}) {
  final box = targetKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return Future.value();
  final overlay = Overlay.of(context, rootOverlay: true);
  final overlayBox = overlay.context.findRenderObject() as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final target = (topLeft & box.size).inflate(8);

  final completer = Completer<void>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoachMarkLayer(
      target: target,
      title: title,
      message: message,
      onDismiss: (tappedTarget) {
        entry.remove();
        completer.complete();
        if (tappedTarget) onTargetTap?.call();
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _CoachMarkLayer extends StatefulWidget {
  const _CoachMarkLayer({
    required this.target,
    required this.title,
    required this.message,
    required this.onDismiss,
  });

  final Rect target;
  final String title;
  final String message;
  final void Function(bool tappedTarget) onDismiss;

  @override
  State<_CoachMarkLayer> createState() => _CoachMarkLayerState();
}

class _CoachMarkLayerState extends State<_CoachMarkLayer>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();
  bool _closing = false;

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Future<void> _close(bool tappedTarget) async {
    if (_closing) return;
    _closing = true;
    await _fade.reverse();
    widget.onDismiss(tappedTarget);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bubbleTop, bubbleBottom) = _bubblePosition(context, widget.target);

    final bubble = Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(widget.message,
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: scheme.onSurfaceVariant)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _close(false),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );

    return FadeTransition(
      opacity: _fade,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _close(widget.target.contains(d.globalPosition)),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _HolePainter(
                  hole: widget.target,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: bubbleTop,
              bottom: bubbleBottom,
              child: bubble,
            ),
          ],
        ),
      ),
    );
  }
}

/// 説明の吹き出しの位置（top / bottom のどちらか一方を返す）。
/// 対象の上下で空いているほうに出す。どちらにも入らないほど対象が大きいときは、
/// 画面の下に重ねて出す（画面の外にはみ出してボタンが押せなくなるのを防ぐ）
(double?, double?) _bubblePosition(BuildContext context, Rect hole) {
  final screen = MediaQuery.sizeOf(context);
  final padding = MediaQuery.paddingOf(context);
  const gap = 12.0;
  const needed = 180.0;
  final spaceBelow = screen.height - padding.bottom - hole.bottom;
  final spaceAbove = hole.top - padding.top;
  if (spaceBelow >= needed && spaceBelow >= spaceAbove) {
    return (hole.bottom + gap, null);
  }
  if (spaceAbove >= needed) {
    return (null, screen.height - hole.top + gap);
  }
  return (null, padding.bottom + 16);
}

class _HolePainter extends CustomPainter {
  _HolePainter({required this.hole, required this.color});

  final Rect hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()
        ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(16))),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HolePainter old) =>
      old.hole != hole || old.color != color;
}

/// 順に案内する 1 項目
class CoachMarkStep {
  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.message,
  });

  final GlobalKey targetKey;
  final String title;
  final String message;
}

/// 画面の部品を 1 つずつ明るくして、「次へ」で順に説明する。
///
/// 対象がスクロールの外にあるときは見える位置まで動かしてから明るくする。
/// 暗い部分のタップでは閉じない（読んでいる途中で消えると困るので、
/// 終わらせるのは「スキップ」か最後の「OK」だけ）。
Future<void> showCoachMarkTour(
  BuildContext context, {
  required List<CoachMarkStep> steps,
}) {
  if (steps.isEmpty) return Future.value();
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<void>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoachMarkTourLayer(
      steps: steps,
      overlayContext: overlay.context,
      onDone: () {
        entry.remove();
        completer.complete();
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _CoachMarkTourLayer extends StatefulWidget {
  const _CoachMarkTourLayer({
    required this.steps,
    required this.overlayContext,
    required this.onDone,
  });

  final List<CoachMarkStep> steps;
  final BuildContext overlayContext;
  final VoidCallback onDone;

  @override
  State<_CoachMarkTourLayer> createState() => _CoachMarkTourLayerState();
}

class _CoachMarkTourLayerState extends State<_CoachMarkTourLayer>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  int _index = 0;
  Rect? _target;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _goTo(0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Future<void> _goTo(int index) async {
    _busy = true;
    final targetContext = widget.steps[index].targetKey.currentContext;
    if (targetContext != null) {
      // 見える位置まで動かす。画面の上寄りに置くと、下に説明を出す余地ができる
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.2,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    if (!mounted) return;
    final rect = _measure(index);
    if (rect == null) {
      // 対象が見つからない項目は飛ばす
      if (index + 1 < widget.steps.length) {
        await _goTo(index + 1);
      } else if (_target == null) {
        widget.onDone(); // 1 つも出せなかった
      } else {
        _busy = false;
        await _finish();
      }
      return;
    }
    setState(() {
      _index = index;
      _target = rect;
    });
    _fade.forward();
    _busy = false;
  }

  Rect? _measure(int index) {
    final box = widget.steps[index].targetKey.currentContext
        ?.findRenderObject() as RenderBox?;
    final overlayBox = widget.overlayContext.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || overlayBox == null) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    return (topLeft & box.size).inflate(6);
  }

  void _next() {
    if (_busy) return;
    if (_index + 1 >= widget.steps.length) {
      _finish();
    } else {
      _goTo(_index + 1);
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    _busy = true;
    await _fade.reverse();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    if (target == null) {
      // 最初の対象を測るまでは、触れないように全面を覆っておく
      return const AbsorbPointer(child: SizedBox.expand());
    }
    final scheme = Theme.of(context).colorScheme;
    final step = widget.steps[_index];
    final isLast = _index == widget.steps.length - 1;

    return FadeTransition(
      opacity: _fade,
      child: TweenAnimationBuilder<Rect?>(
        tween: RectTween(end: target),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        builder: (context, rect, _) {
          final hole = rect ?? target;
          final (bubbleTop, bubbleBottom) = _bubblePosition(context, hole);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _HolePainter(
                      hole: hole,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: bubbleTop,
                  bottom: bubbleBottom,
                  child: Material(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(step.message,
                                style: TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: scheme.onSurfaceVariant)),
                          ),
                          Row(
                            children: [
                              Text('${_index + 1} / ${widget.steps.length}',
                                  style: TextStyle(
                                      fontSize: 12, color: scheme.outline)),
                              const Spacer(),
                              if (!isLast)
                                TextButton(
                                  onPressed: _finish,
                                  child: const Text('スキップ'),
                                ),
                              TextButton(
                                onPressed: isLast ? _finish : _next,
                                child: Text(isLast ? 'OK' : '次へ'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
