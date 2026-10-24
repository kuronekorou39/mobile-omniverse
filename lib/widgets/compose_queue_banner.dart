import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/compose_queue_provider.dart';
import '../providers/draft_list_provider.dart';
import '../screens/compose_screen.dart';
import '../services/draft_service.dart';

/// 投稿キューの進み具合。HomeScreen の本文の下端、下のバーの真上に重ねる。
///
/// 画面いっぱいの帯ではなく、中身ぶんの幅の角の丸い面を中央に浮かせる。
/// 幅は左右の投稿ボタン（FAB）に掛からない範囲に収め、出ても投稿ボタンが
/// 隠れたり動いたりしないようにする。色は状態ごとに ColorScheme の
/// 「〜Container」を使い、投稿中は primary、終わったら secondary、
/// 失敗は error の面にする
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

    // FAB は端から 16、大きさ 56。その内側にさらに 12 空けた幅までにして、
    // 左右どちらに FAB を置く設定でも面が掛からないようにする
    final maxWidth = MediaQuery.sizeOf(context).width - 2 * (16 + 56 + 12);

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: state.hasJobs
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: _Banner(state: state),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _Banner extends ConsumerWidget {
  const _Banner({required this.state});

  final ComposeQueueState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasFailure = state.isAllDone && state.hasFailure;

    final Color bg;
    final Color fg;
    final Widget statusIcon;
    final String message;

    if (hasFailure) {
      // 失敗は見落とすと困るので、成功・処理中より強く出す
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
      statusIcon = Icon(Icons.error_outline, size: 20, color: fg);
      // 横に「再投稿」と閉じるが並ぶので、文は短く
      message = state.totalCount == 1
          ? '投稿に失敗'
          : '${state.failureCount}/${state.totalCount} 件失敗';
    } else if (state.isAllDone) {
      bg = scheme.secondaryContainer;
      fg = scheme.onSecondaryContainer;
      statusIcon = Icon(Icons.check_circle_outline, size: 20, color: fg);
      message = state.totalCount == 1
          ? '投稿しました'
          : '${state.totalCount} 件投稿しました';
    } else {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
      statusIcon = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: fg),
      );
      final current = state.currentlyPosting;
      final position = state.completedCount + 1;
      String atHandle(String h) => h.startsWith('@') ? h : '@$h';
      message = state.totalCount == 1
          ? '投稿しています…'
          : current != null
              ? '${atHandle(current.account.handle)} に投稿中 $position/${state.totalCount}'
              : '投稿しています… ${state.completedCount}/${state.totalCount}';
    }

    return Material(
      color: bg,
      elevation: 2,
      shadowColor: scheme.shadow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 失敗時は行全体を押せるようにしない。閉じようとして押すと
        // 再投稿画面が開いてしまい、閉じる手段が無かった
        onTap: !hasFailure && state.isAllDone
            ? () => ref.read(composeQueueProvider.notifier).dismiss()
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Column(
            // 幅は中身ぶん。進み具合の帯だけは行の幅いっぱいに伸ばす
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  statusIcon,
                  const SizedBox(width: 10),
                  Flexible(
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
                  if (hasFailure) ...[
                    FilledButton(
                      onPressed: () => _retry(context, ref),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      child: const Text('再投稿'),
                    ),
                    IconButton(
                      onPressed: () =>
                          ref.read(composeQueueProvider.notifier).dismiss(),
                      icon: Icon(Icons.close, size: 18, color: fg),
                      tooltip: '閉じる',
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                    ),
                  ] else if (state.isAllDone)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 6),
                      child: Icon(Icons.close, size: 16, color: fg),
                    )
                  else
                    const SizedBox(width: 6),
                ],
              ),
              if (state.totalCount > 1 && !state.isAllDone) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: state.completedCount / state.totalCount,
                      backgroundColor: fg.withValues(alpha: 0.15),
                      color: fg,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    // 一覧を最新化してから最新の失敗下書きを取り出す
    await ref.read(draftListProvider.notifier).reload();
    final list = ref.read(draftListProvider).valueOrNull ?? const [];
    Draft? draft;
    for (final d in list) {
      if (d.isFailureDraft) {
        draft = d;
        break;
      }
    }
    if (!context.mounted) return;
    final picked = draft;
    if (picked == null) {
      // 下書きが見つからなければバナーだけ消す
      ref.read(composeQueueProvider.notifier).dismiss();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          inReplyToPost: picked.inReplyToPost,
          quotedPost: picked.quotedPost,
          draft: picked,
          restoreFailedAccounts: true,
        ),
      ),
    );
  }
}
