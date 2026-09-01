import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../screens/block_scan_result_screen.dart';
import '../services/block_scan_service.dart';
import '../services/follow_db.dart';
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
    final isMine = running != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('ブロック調査'),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'つながっている人のフォロー先をたどって、ブロックの有無を調べます。'
            '数時間かかりますが、途中で止めても続きから再開でき、'
            'その時点までの結果を見られます。',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        if (isMine) _runningCard(running) else _startTile(),
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
          for (final r in _runs) _runTile(r),
      ],
    );
  }

  Widget _startTile() => ListTile(
        leading: const Icon(Icons.travel_explore),
        title: const Text('調査を開始'),
        subtitle: const Text('起点を選びます', style: TextStyle(fontSize: 11)),
        enabled: widget.account != null,
        onTap: widget.account == null ? null : _pickOrigin,
      );

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
              Text('${p.done} / ${p.total} 人',
                  style: const TextStyle(fontSize: 20)),
              Text(
                p.currentHandle == null
                    ? '準備中'
                    : '@${p.currentHandle} を走査中（${p.currentCollected}件）',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
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
    return ListTile(
      dense: true,
      leading: Icon(
        r.isCompleted ? Icons.check_circle_outline : Icons.pause_circle_outline,
        size: 20,
        color: r.isCompleted ? Colors.green : Colors.orange,
      ),
      title: Text(
        '${r.originLabel}起点'
        '${s == null ? '' : ' ・ ブロックされてる ${s.blockedBy}'}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        s == null
            ? ''
            : '${s.doneSources}/${s.totalSources}人'
                '${r.isCompleted ? '' : ' ・ 未完了'}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (resumable)
            TextButton(
              onPressed: () => _resume(r),
              child: const Text('再開', style: TextStyle(fontSize: 12)),
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

    // 起点は取得済みの一覧をそのまま使う。無いものは選ばせない
    final choices = <({String origin, String label, int? count})>[
      (
        origin: 'following',
        label: 'フォロー',
        count: following?.collectedCount
      ),
      (
        origin: 'followers',
        label: 'フォロワー',
        count: followers?.collectedCount
      ),
      (
        origin: 'mutual',
        label: '相互',
        count: (followers != null && following != null)
            ? (await db.relationCounts(
                    followersSnapshotId: followers.id,
                    followingSnapshotId: following.id))
                .mutual
            : null
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
                      : '${c.count}人のフォロー先をたどります',
                  style: const TextStyle(fontSize: 11),
                ),
                enabled: c.count != null && c.count! > 0,
                onTap: () => Navigator.pop(ctx, c.origin),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final count = choices.firstWhere((c) => c.origin == picked).count ?? 0;
    // 十数時間かかることがあるので、規模を見せてから始める
    final ok = await confirmDialog(
      context,
      title: 'ブロック調査を開始',
      message: '$count人のフォロー先を1人ずつたどります。\n\n'
          'フォローが1万を超える相手は飛ばします。'
          '数時間から十数時間かかることがあります。\n'
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
      await _scan.resume(account: account, runId: run.id);
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e', type: SnackType.error);
    }
    await _load();
    widget.onChanged();
  }

  Widget _header(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            )),
      );
}
