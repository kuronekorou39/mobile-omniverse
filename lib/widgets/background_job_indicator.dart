import 'package:flutter/material.dart';

import '../services/block_scan_service.dart';
import '../services/follow_capture_engine.dart';
import '../services/follow_capture_job_service.dart';

/// 裏で走っている収集を、タイムラインからも分かるようにする。
///
/// フォロー/フォロワー取得もつながり調査も数時間から数日かかる。対象の
/// 画面を離れると何も見えなくなり、動いているのか止まったのか分からない。
/// 進み具合を小さく出し、押せば内訳を見せる。
class BackgroundJobIndicator extends StatelessWidget {
  const BackgroundJobIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final job = FollowCaptureJobService.instance;
    final scan = BlockScanService.instance;

    // どちらも ValueNotifier なので、2 つ重ねて両方を見る
    return ValueListenableBuilder<FollowJobProgress?>(
      valueListenable: job.progress,
      builder: (context, capture, _) {
        return ValueListenableBuilder<BlockScanProgress?>(
          valueListenable: scan.progress,
          builder: (context, blockScan, _) {
            if (capture == null && blockScan == null) {
              return const SizedBox.shrink();
            }
            return _Badge(capture: capture, scan: blockScan);
          },
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.capture, required this.scan});

  final FollowJobProgress? capture;
  final BlockScanProgress? scan;

  /// 進みの割合。取れなければ null（くるくる回すだけ）
  double? get _ratio {
    final s = scan;
    if (s != null && s.total > 0) return s.done / s.total;
    return null;
  }

  String get _label {
    final s = scan;
    if (s != null) {
      return s.cancelling
          ? 'つながり調査を中断しています'
          : 'つながり調査 @${s.targetHandle}\n'
              '${s.done} / ${s.total} 人';
    }
    final c = capture!;
    final kind = c.kind == FollowListKind.followers ? 'フォロワー' : 'フォロー';
    return c.cancelling
        ? '$kind の取得を中断しています'
        : '@${c.targetHandle} の$kind\n${c.collected} 件';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: _label,
      triggerMode: TooltipTriggerMode.tap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: _ratio,
                    strokeWidth: 2,
                    color: scheme.tertiary,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                Icon(
                  scan != null ? Icons.hub : Icons.groups_outlined,
                  size: 11,
                  color: scheme.tertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
