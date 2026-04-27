import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/compose_queue_provider.dart';

/// 投稿キューの進捗を表示する細いバナー。
/// HomeScreen の bottomNavigationBar の真上に常駐させる前提。
class ComposeQueueBanner extends ConsumerStatefulWidget {
  const ComposeQueueBanner({super.key});

  @override
  ConsumerState<ComposeQueueBanner> createState() =>
      _ComposeQueueBannerState();
}

class _ComposeQueueBannerState extends ConsumerState<ComposeQueueBanner> {
  Timer? _autoDismissTimer;
  bool _wasAllSuccess = false;

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoDismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      ref.read(composeQueueProvider.notifier).dismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(composeQueueProvider);

    // 全成功完了の瞬間に 3 秒タイマーをセット（一度だけ）
    final isAllSuccess = state.isAllDone && !state.hasFailure;
    if (isAllSuccess && !_wasAllSuccess) {
      _scheduleAutoDismiss();
    } else if (!isAllSuccess) {
      _autoDismissTimer?.cancel();
    }
    _wasAllSuccess = isAllSuccess;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: state.hasJobs
          ? _Banner(state: state)
          : const SizedBox(width: double.infinity),
    );
  }
}

class _Banner extends ConsumerWidget {
  const _Banner({required this.state});

  final ComposeQueueState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final Color bg;
    final Color fg;
    final Widget statusIcon;
    final String message;

    if (state.isAllDone && state.hasFailure) {
      bg = Colors.red.withValues(alpha: 0.15);
      fg = Colors.red.shade700;
      statusIcon = Icon(Icons.error_outline, size: 18, color: fg);
      message = state.totalCount == 1
          ? '投稿に失敗しました'
          : '${state.failureCount}/${state.totalCount} 件失敗';
    } else if (state.isAllDone) {
      bg = Colors.green.withValues(alpha: 0.15);
      fg = Colors.green.shade700;
      statusIcon = Icon(Icons.check_circle_outline, size: 18, color: fg);
      message = state.totalCount == 1
          ? '投稿しました'
          : '${state.totalCount} 件投稿しました';
    } else {
      bg = theme.colorScheme.primary.withValues(alpha: 0.10);
      fg = theme.colorScheme.primary;
      statusIcon = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: fg),
      );
      final current = state.currentlyPosting;
      final position = state.completedCount + 1;
      message = current != null
          ? '@${current.account.handle} 投稿中… $position/${state.totalCount}'
          : '投稿中… ${state.completedCount}/${state.totalCount}';
    }

    return Material(
      color: bg,
      child: InkWell(
        onTap: state.isAllDone
            ? () => ref.read(composeQueueProvider.notifier).dismiss()
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  statusIcon,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        color: fg,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (state.isAllDone)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.close, size: 16, color: fg),
                    ),
                ],
              ),
              if (state.totalCount > 1) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: state.completedCount / state.totalCount,
                    backgroundColor: fg.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(fg),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
