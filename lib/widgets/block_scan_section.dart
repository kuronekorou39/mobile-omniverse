import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../screens/block_scan_result_screen.dart';
import '../services/account_storage_service.dart';
import '../services/block_scan_service.dart';
import '../services/follow_db.dart';
import '../services/scan_estimate.dart';
import '../utils/app_snackbar.dart';
import '../utils/confirm_dialog.dart';
import '../utils/number_format.dart';
import 'follow_section_header.dart';
import 'skeleton.dart';

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

  /// 新しく始める調査に使うアカウント。null なら開始できない。
  /// 再開は調査を始めたときのアカウントで走らせるので、これは使わない
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

  /// 開閉を自分で選んだか。null のあいだは、調査中や未完了があるときだけ開く
  bool? _expanded;
  static const _prefExpanded = 'block_scan_section_expanded';

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
    final prefs = await SharedPreferences.getInstance();
    final expanded = prefs.getBool(_prefExpanded);
    if (!mounted) return;
    setState(() {
      _expanded = expanded;
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
    final hasUnfinished = _runs.any((r) => !r.isCompleted);
    // 決めていなければ、気にしておくべきものがあるときだけ開いておく
    final open = _expanded ?? (isMine || hasUnfinished);

    return Padding(
      // 下に続くまとまりとの間隔。Bluesky では丸ごと出さないので内側に持つ
      padding: const EdgeInsets.only(bottom: FollowSectionHeader.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 3 行の説明は毎回読むものではないので畳む
          FollowSectionHeader(
            'つながり調査',
            info: 'つながっている人のフォロー先をたどって、'
                'ブロック・ミュートの有無を調べます。\n'
                '数時間かかりますが、途中で止めても続きから再開でき、'
                'その時点までの結果を見られます。\n\n'
                'フォローが ${formatNumber(FollowDb.blockScanFriendLimit)} 人を'
                '超える相手は飛ばします（1 人で何時間もかかるため）。\n'
                '「延べ」の件数は、起点の人たちのフォロー数を足したものです。'
                '同じ人が何度も数えられるので、実際の人数はもっと少なくなります。'
                '所要時間と保存容量の目安はこの延べ件数から出しています'
                '（1 件あたり約 ${ScanEstimate.bytesPerItem.round()} バイト）。\n'
                '調査の結果は「保存容量」の上限とは別に数えるので、'
                '上限を超えても取得の履歴は消えません。',
            expanded: open,
            onToggle: () => _setExpanded(!open),
            summary: isMine
                ? '調査中'
                : hasUnfinished
                    ? '未完了あり'
                    : _runs.isEmpty
                        ? null
                        : '${_runs.length}件',
          ),
          if (open) ..._body(running, isMine, otherRunning, hasUnfinished),
        ],
      ),
    );
  }

  Future<void> _setExpanded(bool value) async {
    setState(() => _expanded = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefExpanded, value);
  }

  List<Widget> _body(BlockScanProgress? running, bool isMine,
          bool otherRunning, bool hasUnfinished) =>
      [
          if (isMine) _runningCard(running!),
          if (otherRunning) _otherRunningNote(running!),
          if (_loading) ...[
            // 調査の記録 1 行ぶんの形で待つ
            const SkeletonBox(height: 72, radius: 16),
            const SizedBox(height: 12),
          ] else if (_runs.isNotEmpty) ...[
            _runList(),
            const SizedBox(height: 12),
          ],
          if (!isMine)
            _startButton(
              blocked: otherRunning,
              // 続きがあるうちは、そちらが主。新規は控えめに出す
              hasResumable: hasUnfinished,
            ),
      ];

  /// 別の対象を調べている間は、この対象の様子ではないことをはっきり出す。
  /// 走査は 1 本ずつなので、終わるまでここでは始められない
  Widget _otherRunningNote(BlockScanProgress p) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
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

  Widget _runningCard(BlockScanProgress p) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
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
                  Text('${formatNumber(p.done)} / ${formatNumber(p.total)} 人',
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
                    : '@${p.currentHandle} を走査中（${formatNumber(p.currentCollected)}件）',
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

  /// 調査の記録はどれも同じ性質の行なので、ひとつの面にまとめる
  Widget _runList() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, r) in _runs.indexed) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                  color: scheme.outlineVariant),
            _runRow(r),
          ],
        ],
      ),
    );
  }

  Account? _accountOf(String id) => AccountStorageService.instance.accounts
      .where((a) => a.id == id)
      .firstOrNull;

  /// 行の中で押せるのは「再開」だけにする。削除は結果画面のメニューに置く
  Widget _runRow(BlockRun r) {
    final s = _stats[r.id];
    final resumable = !r.isCompleted && !_scan.isRunning;
    final scheme = Theme.of(context).colorScheme;
    final ranBy =
        r.sessionAccountId == null ? null : _accountOf(r.sessionAccountId!);
    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => BlockScanResultScreen(run: r)));
        await _load();
        // 結果画面で調査を消すと、未完了かどうかが変わる
        widget.onChanged();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r.originLabel}起点',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    s == null
                        ? '集計中…'
                        : '被ブロック ${formatNumber(s.blockedBy)} ・ '
                            '${formatNumber(s.doneSources)}/${formatNumber(s.totalSources)}人',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  // 結果は「このアカウントから見た関係」なので、誰で調べたかを残す
                  Text(
                    [
                      if (ranBy != null) '${ranBy.handle} で調査',
                      r.isCompleted ? '完了' : '未完了',
                    ].join(' ・ '),
                    style: TextStyle(
                        fontSize: 11,
                        color: r.isCompleted
                            ? scheme.onSurfaceVariant
                            : scheme.tertiary),
                  ),
                ],
              ),
            ),
            // 下に「調査を開始」の大きなボタンがあるので、テキストのままだと
            // 見劣りして、続きがあるのに新しく始めてしまう
            if (resumable)
              FilledButton.tonalIcon(
                onPressed: () => _resume(r),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('再開'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
              )
            else
              Icon(Icons.chevron_right,
                  size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
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
        origin: 'both',
        label: 'フォロー＋フォロワー',
        count: (followers != null && following != null)
            ? await db.unionCount(
                followersSnapshotId: followers.id,
                followingSnapshotId: following.id)
            : null,
        items: (followers != null && following != null)
            ? await db.plannedItemsForUnion(
                followersSnapshotId: followers.id,
                followingSnapshotId: following.id)
            : 0,
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
                      : '${formatNumber(c.count!)}人のフォロー先をたどります'
                          '${c.items > 0 ? '（延べ${formatNumber(c.items)}件・保存 ${ScanEstimate(items: c.items).storageLabel}）' : ''}',
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
      message: '${formatNumber(count)}人のフォロー先を1人ずつたどります'
          '${chosen.items > 0 ? '（延べ${formatNumber(chosen.items)}件。同じ人が何度も数えられるので、実際の人数はもっと少なくなります）' : ''}。\n'
          '${chosen.items > 0 ? '目安 ${estimate.label}、保存に ${estimate.storageLabel} ほど使います。'
              '通信状況や制限、相手の重なり方で前後します。\n' : ''}\n'
          'フォローが ${formatNumber(FollowDb.blockScanFriendLimit)} 人を超える相手は飛ばします。\n'
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

  Future<void> _resume(BlockRun run) async {
    // 結果は「調査を始めたアカウントから見た関係」。今選ばれている
    // アカウントで続けると、別の視点の結果が同じ調査に混ざる。
    // 実行アカウントを記録していなかった頃の調査だけ、今のもので走らせる
    final startedBy = run.sessionAccountId;
    final account =
        startedBy == null ? widget.account : _accountOf(startedBy);
    if (account == null) {
      showAppSnackBar(
          context,
          '調査を始めたアカウントが見つかりません。'
          'ログインし直すか、新しく調査を始めてください',
          type: SnackType.error);
      return;
    }
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
