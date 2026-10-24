import 'package:flutter/material.dart';

import '../services/block_scan_service.dart';
import '../services/follow_capture_engine.dart';
import '../services/follow_capture_job_service.dart';
import '../services/user_detail_service.dart';
import '../utils/number_format.dart';

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
    final detail = UserDetailService.instance;

    // どれも ValueNotifier なので、重ねて全部を見る
    return ValueListenableBuilder<FollowJobProgress?>(
      valueListenable: job.progress,
      builder: (context, capture, _) {
        return ValueListenableBuilder<BlockScanProgress?>(
          valueListenable: scan.progress,
          builder: (context, blockScan, _) {
            return ValueListenableBuilder<UserDetailProgress?>(
              valueListenable: detail.progress,
              builder: (context, details, _) {
                if (capture == null && blockScan == null && details == null) {
                  return const SizedBox.shrink();
                }
                return _Badge(
                    capture: capture, scan: blockScan, detail: details);
              },
            );
          },
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.capture, required this.scan, required this.detail});

  final FollowJobProgress? capture;
  final BlockScanProgress? scan;
  final UserDetailProgress? detail;

  /// 進みの割合。取れなければ null（くるくる回すだけ）
  double? get _ratio {
    final s = scan;
    if (s != null && s.total > 0) return s.done / s.total;
    final d = detail;
    if (d != null && d.total > 0) return d.done / d.total;
    return null;
  }

  String get _label {
    final s = scan;
    if (s != null) {
      return s.cancelling
          ? 'つながり調査を中断しています'
          : 'つながり調査 @${s.targetHandle}\n'
              '${formatNumber(s.done)} / ${formatNumber(s.total)} 人';
    }
    final d = detail;
    if (d != null) {
      return d.cancelling
          ? '詳しい情報の取得を中断しています'
          : '詳しい情報 @${d.targetHandle}\n'
              '${formatNumber(d.done)} / ${formatNumber(d.total)} 人';
    }
    final c = capture!;
    final kind = c.kind == FollowListKind.followers ? 'フォロワー' : 'フォロー';
    return c.cancelling
        ? '$kind の取得を中断しています'
        : '@${c.targetHandle} の$kind\n${formatNumber(c.collected)} 件';
  }

  IconData get _icon {
    if (scan != null) return Icons.hub;
    if (detail != null) return Icons.person_search;
    return Icons.groups_outlined;
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
                Icon(_icon, size: 11, color: scheme.tertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
