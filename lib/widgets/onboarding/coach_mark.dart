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
    final screen = MediaQuery.sizeOf(context);
    // 対象が画面の上半分なら説明は下に、下半分なら上に出す
    final below = widget.target.center.dy < screen.height / 2;
    const gap = 12.0;

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
              top: below ? widget.target.bottom + gap : null,
              bottom: below ? null : screen.height - widget.target.top + gap,
              child: bubble,
            ),
          ],
        ),
      ),
    );
  }
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
