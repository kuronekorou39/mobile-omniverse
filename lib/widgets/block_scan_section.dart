import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../screens/block_scan_result_screen.dart';
import '../services/block_scan_service.dart';
import '../services/follow_db.dart';
import '../services/scan_estimate.dart';
import '../utils/app_snackbar.dart';
import '../utils/confirm_dialog.dart';

/// 対象画面に置く「ブロック調査」のひとかたまり。
///
/// つながっている人のフォロー先をたどるので、数千人が起点だと十数時間
/// かかる。始める前に規模を見せ、途中でも結果を見られるようにしておく。
class BlockScanSection extends StatefulWidget {
  const BlockScanSection({
    super.key,
    required this.service,
    required this.handle,
    required this.account,
    required this.onChanged,
  });

  final SnsService service;
  final String handle;

  /// 走査に使うアカウント。null なら開始できない
  final Account? account;

  /// 調査の開始・終了で対象画面を読み直してもらう
  final VoidCallback onChanged;

  @override
  State<BlockScanSection> createState() => _BlockScanSectionState();
}

class _BlockScanSectionState extends State<BlockScanSection> {
  final _scan = BlockScanService.instance;

  List<BlockRun> _runs = [];
  final Map<int, BlockRunProgress> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scan.progress.addListener(_onProgress);
    _load();
  }

  @override
  void dispose() {
    _scan.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final db = FollowDb.instance;
    final runs = await db.listBlockRuns(
        service: widget.service, targetHandle: widget.handle, limit: 5);
    final stats = <int, BlockRunProgress>{};
    for (final r in runs) {
      stats[r.id] = await db.blockRunProgress(r.id);
    }
    if (!mounted) return;
    setState(() {
      _runs = runs;
      _stats
        ..clear()
        ..addAll(stats);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // X の一覧にしか関係の項目が載らないので、Bluesky では出さない
    if (widget.service != SnsService.x) return const SizedBox.shrink();

    final running = _scan.progress.value;
    // 調査は 1 本しか走らないので、別の対象を調べている間もここに
    // 進捗が届く。自分の対象でなければ、進捗ではなく「塞がっている」
    // ことを示す。同じグルグルを出すと自分が動いているように見える
    final isMine = running != null && running.targetHandle == widget.handle;
    final otherRunning =
        running != null && running.targetHandle != widget.handle;

    final scheme = Theme.of(context).colorScheme;
    // フォロー/フォロワー取得とは別の機能なので、面を変えて隔離する
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 22, 8, 0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('つながり調査',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              // 3 行の説明は毎回読むものではないので畳む
              Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                message: 'つながっている人のフォロー先をたどって、'
                    'ブロック・ミュートの有無を調べます。\n'
                    '数時間かかりますが、途中で止めても続きから再開でき、'
                    'その時点までの結果を見られます。',
                child: Icon(Icons.info_outline,
                    size: 18, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isMine) _runningCard(running),
          if (otherRunning) _otherRunningNote(running),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            for (final r in _runs) ...[
              _runTile(r),
              const SizedBox(height: 8),
            ],
          if (!isMine) ...[
            const SizedBox(height: 12),
            _startButton(
              blocked: otherRunning,
              // 続きがあるうちは、そちらが主。新規は控えめに出す
              hasResumable: _runs.any((r) => !r.isCompleted),
            ),
          ],
        ],
      ),
    );
  }

  /// 別の対象を調べている間は、この対象の様子ではないことをはっきり出す。
  /// 走査は 1 本ずつなので、終わるまでここでは始められない
  Widget _otherRunningNote(BlockScanProgress p) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${p.targetHandle} を調査中',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  'この対象ではありません。終わるまで始められません',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _startButton({bool blocked = false, bool hasResumable = false}) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.account != null && !blocked;
    final label = blocked
        ? '他の調査が終わるまで待機'
        : hasResumable
            ? '新しく調査を始める'
            : '調査を開始';
    // 続きがあるときは、上の「再開」を主にして、ここは枠を薄くする
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: enabled ? _pickOrigin : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          side: BorderSide(
            color: !enabled
                ? scheme.outlineVariant
                : hasResumable
                    ? scheme.outlineVariant
                    : scheme.primary,
            width: hasResumable ? 1 : 1.5,
          ),
          foregroundColor: hasResumable ? scheme.onSurfaceVariant : null,
          textStyle: TextStyle(
            fontSize: hasResumable ? 13 : 14,
            fontWeight: hasResumable ? FontWeight.w500 : FontWeight.bold,
          ),
        ),
        child: Text(label),
      ),
    );
  }

  /// 残りの延べ件数と実測の速さから、あとどれくらいかを出す
  String? _remainingLabel(BlockScanProgress p) {
    if (p.remainingItems <= 0) return null;
    final e = ScanEstimate(items: p.remainingItems);
    final label = e.label;
    return label == '—' ? null : label;
  }

  Widget _runningCard(BlockScanProgress p) => Card(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.cancelling ? '調査を中断しています…' : '調査中',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: p.cancelling ? null : _scan.cancel,
                  child: const Text('中断'),
                ),
              ]),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${p.done} / ${p.total} 人',
                      style: const TextStyle(fontSize: 20)),
                  const Spacer(),
                  // 何時間待つのかは、途中で一番知りたい情報
                  if (_remainingLabel(p) case final left?)
                    Text('残り $left',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                ],
              ),
              Text(
                p.currentHandle == null
                    ? '準備中'
                    : '@${p.currentHandle} を走査中（${p.currentCollected}件）',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              if (p.total > 0) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                      minHeight: 3, value: p.done / p.total),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _runTile(BlockRun r) {
    final s = _stats[r.id];
    final resumable = !r.isCompleted && !_scan.isRunning;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      // カードの面に載るので、行ごとに面を持たせて沈ませる
      tileColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Icon(
          r.isCompleted
              ? Icons.check_circle_outline
              : Icons.pause_circle_outline,
          size: 20,
          color: r.isCompleted ? scheme.primary : scheme.tertiary,
        ),
      ),
      title: Text(
        '${r.originLabel}起点'
        '${s == null ? '' : ' ・ 被ブロック ${s.blockedBy}'}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        s == null
            ? ''
            : '${s.doneSources}/${s.totalSources}人'
                '${r.isCompleted ? '' : ' ・ 未完了'}',
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 下に「調査を開始」の大きなボタンがあるので、テキストのままだと
          // 見劣りして、続きがあるのに新しく始めてしまう
          if (resumable)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilledButton.tonalIcon(
                onPressed: () => _resume(r),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('再開'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          // 調査は GB 単位になるので、消す手段は必ず出しておく
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'この調査を削除',
            visualDensity: VisualDensity.compact,
            onPressed: _scan.isRunning ? null : () => _confirmDelete(r, s),
          ),
        ],
      ),
      onTap: () async {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => BlockScanResultScreen(run: r)));
        await _load();
      },
    );
  }

  Future<void> _pickOrigin() async {
    final account = widget.account;
    if (account == null) return;

    final db = FollowDb.instance;
    final followers =
        await db.latestCompleted(widget.service, widget.handle, 'followers');
    final following =
        await db.latestCompleted(widget.service, widget.handle, 'following');
    if (!mounted) return;

    // 何時間かかるかは選ぶ前に知りたい。起点の人たちのフォロー数を
    // 足した延べ件数から見積もる
    // 起点は取得済みの一覧をそのまま使う。無いものは選ばせない
    final choices = <({String origin, String label, int? count, int items})>[
      (
        origin: 'following',
        label: 'フォロー',
        count: following?.collectedCount,
        items: following == null
            ? 0
            : await db.plannedItemsForSnapshot(following.id),
      ),
      (
        origin: 'followers',
        label: 'フォロワー',
        count: followers?.collectedCount,
        items: followers == null
            ? 0
            : await db.plannedItemsForSnapshot(followers.id),
      ),
      (
        origin: 'mutual',
        label: '相互',
        count: (followers != null && following != null)
            ? (await db.relationCounts(
                    followersSnapshotId: followers.id,
                    followingSnapshotId: following.id))
                .mutual
            : null,
        items: (followers != null && following != null)
            ? await db.plannedItemsForMutual(
                followersSnapshotId: followers.id,
                followingSnapshotId: following.id)
            : 0,
      ),
    ];
    if (!mounted) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('どこを起点に調べますか',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final c in choices)
              ListTile(
                dense: true,
                title: Text(c.label),
                subtitle: Text(
                  c.count == null
                      ? 'まだ取得していません'
                      : '${c.count}人のフォロー先をたどります'
                          '${c.items > 0 ? '（延べ${c.items}件）' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                // かかる時間が選ぶ基準になるので、右端に出す
                trailing: c.items > 0
                    ? Text(
                        ScanEstimate(items: c.items).label,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      )
                    : null,
                enabled: c.count != null && c.count! > 0,
                onTap: () => Navigator.pop(ctx, c.origin),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final chosen = choices.firstWhere((c) => c.origin == picked);
    final count = chosen.count ?? 0;
    final estimate = ScanEstimate(items: chosen.items);
    // 十数時間かかることがあるので、規模と目安を見せてから始める
    final ok = await confirmDialog(
      context,
      title: 'つながり調査を開始',
      message: '$count人のフォロー先を1人ずつたどります'
          '${chosen.items > 0 ? '（延べ${chosen.items}件）' : ''}。\n'
          '${chosen.items > 0 ? '目安 ${estimate.label}。これまでの取得の速さから見積もった'
              'ものなので、通信状況や制限で前後します。\n' : ''}\n'
          'フォローが1万を超える相手は飛ばします。\n'
          '中断しても続きから再開でき、途中までの結果も見られます。',
      confirmLabel: '開始',
    );
    if (!ok || !mounted) return;

    try {
      final runId = await _scan.start(
        account: account,
        service: widget.service,
        handle: widget.handle,
        origin: picked,
      );
      if (!mounted) return;
      if (runId == null) {
        showAppSnackBar(context, '起点になる一覧がありません', type: SnackType.error);
      }
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e', type: SnackType.error);
    }
    await _load();
    widget.onChanged();
  }

  Future<void> _confirmDelete(BlockRun run, BlockRunProgress? s) async {
    final ok = await confirmDialog(
      context,
      title: 'この調査を削除',
      message: '${run.originLabel}起点の調査'
          '${s == null ? '' : '（${s.doneSources}/${s.totalSources}人ぶん）'}'
          'を削除します。\n\n'
          '集めた結果はすべて失われ、元に戻せません。'
          '走らせ直す場合は最初からになります。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok) return;
    try {
      await FollowDb.instance.deleteBlockRun(run.id);
    } catch (e) {
      if (mounted) showAppSnackBar(context, '削除に失敗しました: $e', type: SnackType.error);
      return;
    }
    if (mounted) showAppSnackBar(context, '調査を削除しました');
    await _load();
    widget.onChanged();
  }

  Future<void> _resume(BlockRun run) async {
    final account = widget.account;
    if (account == null) return;
    try {
      await _scan.resume(
          account: account,
          runId: run.id,
          targetHandle: run.targetHandle);
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e', type: SnackType.error);
    }
    await _load();
    widget.onChanged();
  }

}
