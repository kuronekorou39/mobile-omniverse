import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../screens/block_scan_result_screen.dart';
import '../services/account_storage_service.dart';
import '../services/block_scan_service.dart';
import '../services/debug_log_service.dart';
import '../services/fetch_jobs.dart';
import '../services/follow_db.dart';
import '../services/scan_estimate.dart';
import '../utils/app_snackbar.dart';
import '../utils/number_format.dart';
import 'fetch_start_dialog.dart';
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
    FetchJobs.instance.current.addListener(_onProgress);
    _load();
  }

  /// 待機中だけ 1 秒ごとに描き直して、残り秒数を進める
  Timer? _waitTick;

  @override
  void dispose() {
    _waitTick?.cancel();
    _scan.progress.removeListener(_onProgress);
    FetchJobs.instance.current.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (!mounted) return;
    final waiting = _scan.progress.value?.waitingReason != null;
    if (waiting && _waitTick == null) {
      _waitTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!waiting) {
      _waitTick?.cancel();
      _waitTick = null;
    }
    setState(() {});
  }

  Future<void> _load() async {
    final db = FollowDb.instance;
    final sw = Stopwatch()..start();
    try {
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
      DebugLogService.instance.log('BlockScan',
          '欄の読み込み ${runs.length} 件 ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      // 失敗しても骨組みのまま残さない。一覧が空のまま出るだけにする
      DebugLogService.instance.log('BlockScan',
          '欄の読み込み失敗 (${sw.elapsedMilliseconds}ms): $e');
      if (mounted) setState(() => _loading = false);
    }
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
    // 別の対象の調査も、フォロー/フォロワー取得や詳しい情報の取得も、
    // 走っている間はここから始められない
    final blockedBy = isMine ? null : FetchJobs.instance.current.value;
    final hasUnfinished = _runs.any((r) => !r.isCompleted);
    // 決めていなければ、気にしておくべきものがあるときだけ開いておく
    final open = _expanded ?? (isMine || hasUnfinished);

    return Padding(
      // 下に続くまとまりとの間隔。Bluesky では丸ごと出さないので内側に持つ
      padding: const EdgeInsets.only(bottom: FollowSectionHeader.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 説明は要点だけ。細かい決まりは始めるときの画面で見せる
          FollowSectionHeader(
            'つながり調査',
            info: 'つながっている人のフォロー先をたどって、'
                'ブロック・ミュートの有無を調べます。\n'
                '数時間かかりますが、途中で止めても続きから再開できます。\n'
                'フォローが ${formatNumber(FollowDb.blockScanFriendLimit)} 人を'
                '超える相手は飛ばします。\n'
                'ブロック・ミュートの関係は必ず記録します。'
                '「人気」はつながりの中でよくフォローされている人、'
                '「つながり」はその人を誰がフォローしているかです。',
            expanded: open,
            onToggle: () => _setExpanded(!open),
            summary: isMine
                ? '調査中'
                : hasUnfinished
                    ? '未完了あり'
                    : null,
          ),
          if (open)
            FollowSectionBody(
                children: _body(running, isMine, blockedBy, hasUnfinished)),
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
          RunningFetch? blockedBy, bool hasUnfinished) =>
      [
          if (isMine) _runningCard(running!),
          if (_loading) ...[
            // 調査の記録 1 行ぶんの形で待つ
            const SkeletonBox(height: 72, radius: 16),
            const SizedBox(height: 12),
          ] else if (_runs.isNotEmpty) ...[
            _runList(),
            const SizedBox(height: 8),
          ],
          // 「以前の調査」の切り替えと開始ボタンは 1 行に左右で並べる
          if (!isMine || _olderRuns.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _olderToggle(),
                  ),
                ),
                if (!isMine)
                  _startButton(blockedBy: blockedBy),
              ],
            ),
      ];

  Widget _startButton({RunningFetch? blockedBy}) => FetchStartButton(
        onPressed:
            widget.account != null && blockedBy == null ? _pickOrigin : null,
        label: blockedBy?.waitLabel ?? '取得する',
      );

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
              // 止まって見えるときに、待っているだけだと分かるように。
              // 高さは常に確保して、出入りで下の棒がずれないようにする
              SizedBox(
                height: 16,
                width: double.infinity,
                child: p.waitingReason == null
                    ? null
                    : Text(
                        _waitingLabel(p.waitingReason!, p.waitingUntil),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.tertiary),
                      ),
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

  static String _waitingLabel(String reason, DateTime? until) {
    final left = until?.difference(DateTime.now());
    if (left == null || left.isNegative) return '待機中: $reason';
    return '待機中: $reason（あと${left.inSeconds}秒）';
  }

  /// 調査の記録はどれも同じ性質の行なので、ひとつの面にまとめる
  /// 以前の調査まで開いているか
  bool _showOlder = false;

  /// ここに並べる調査。最新の 1 件だけにして、履歴の山にしない。
  /// 最新が完了していて、その前に未完了が残っているなら、再開の入口と
  /// してそれも出す。それ以外は「以前の調査」から開く
  List<BlockRun> get _shownRuns {
    if (_runs.isEmpty) return const [];
    final shown = [_runs.first];
    if (_runs.first.isCompleted) {
      final unfinished = _runs.skip(1).where((r) => !r.isCompleted).firstOrNull;
      if (unfinished != null) shown.add(unfinished);
    }
    return shown;
  }

  /// 新しいほうから出している調査以外（以前の調査）
  List<BlockRun> get _olderRuns {
    final shown = _shownRuns;
    return _runs.where((r) => !shown.contains(r)).toList();
  }

  Widget _runList() {
    final scheme = Theme.of(context).colorScheme;
    final rows = _showOlder ? [..._shownRuns, ..._olderRuns] : _shownRuns;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, r) in rows.indexed) ...[
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

  /// 隠した調査も消せるように、入口だけ控えめに残す。無ければ何も出さない
  Widget _olderToggle() {
    final older = _olderRuns;
    if (older.isEmpty) return const SizedBox.shrink();
    return TextButton(
      onPressed: () => setState(() => _showOlder = !_showOlder),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        textStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
      ),
      child: Text(_showOlder ? '以前の調査を隠す' : '以前の調査 ${older.length}件'),
    );
  }

  Account? _accountOf(String id) => AccountStorageService.instance.accounts
      .where((a) => a.id == id)
      .firstOrNull;

  /// 行の中で押せるのは「再開」だけにする。削除は結果画面のメニューに置く
  Widget _runRow(BlockRun r) {
    final s = _stats[r.id];
    final resumable = !r.isCompleted && !FetchJobs.instance.isBusy;
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
                      // 全部は記録していない調査だと分かるようにしておく
                      if (r.recordLabel != null) '記録: ${r.recordLabel}',
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
            // 下に「取得する」のボタンがあるので、テキストのままだと
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
        label: '両方',
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

    // 起点と記録する内容を 1 枚で選ぶ。何時間かかるか・どれだけ残るかは
    // 選び方で変わるので、下の 1 行に出し直す
    final result = await showDialog<({String origin, BlockScanRecord record})>(
      context: context,
      builder: (_) => _ScanStartDialog(choices: choices),
    );
    if (result == null || !mounted) return;
    final picked = result.origin;
    final record = result.record;

    try {
      final runId = await _scan.start(
        account: account,
        service: widget.service,
        handle: widget.handle,
        origin: picked,
        keepEdges: record.keepEdges,
        keepPopular: record.keepPopular,
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

/// 調査で何を記録するか。開始ダイアログで選ぶ。
/// ブロック・ミュートの関係は常に記録するので、ここには持たない
class BlockScanRecord {
  const BlockScanRecord({required this.keepPopular, required this.keepEdges});

  /// 「人気」（相手ごとの被フォロー人数）を積むか
  final bool keepPopular;

  /// 誰が誰をフォローしているかを全部残すか
  final bool keepEdges;
}

typedef _ScanOrigin = ({String origin, String label, int? count, int items});

/// つながり調査の開始。起点と記録する内容を選び、規模を見てから始める
class _ScanStartDialog extends StatefulWidget {
  const _ScanStartDialog({required this.choices});

  final List<_ScanOrigin> choices;

  @override
  State<_ScanStartDialog> createState() => _ScanStartDialogState();
}

class _ScanStartDialogState extends State<_ScanStartDialog> {
  late _ScanOrigin _chosen = widget.choices.firstWhere(
      (c) => (c.count ?? 0) > 0,
      orElse: () => widget.choices.first);
  late bool _keepPopular;
  late bool _keepEdges;

  @override
  void initState() {
    super.initState();
    // GB 単位になりそうな項目は外しておく
    final e = ScanEstimate(items: _chosen.items);
    const gb = 1024 * 1024 * 1024;
    final hasItems = e.items > 0;
    _keepPopular = !hasItems || e.totalBytes(popular: true, edges: false) < gb;
    _keepEdges = !hasItems || e.totalBytes(popular: true, edges: true) < gb;
  }

  @override
  Widget build(BuildContext context) {
    final e = ScanEstimate(items: _chosen.items);
    final count = _chosen.count ?? 0;
    return FetchStartDialog(
      title: 'つながり調査',
      targets: [
        for (final c in widget.choices)
          FetchTargetChoice(c.origin, c.label,
              count: c.count,
              detail: c.items > 0 ? ScanEstimate(items: c.items).label : null,
              enabled: (c.count ?? 0) > 0),
      ],
      selected: _chosen.origin,
      onSelected: (v) => setState(
          () => _chosen = widget.choices.firstWhere((c) => c.origin == v)),
      optionsLabel: '記録する内容',
      options: [
        FetchOption('人気',
            value: _keepPopular,
            // つながりを残すなら人気は必ず付いてくる
            onChanged: _keepEdges
                ? null
                : (v) => setState(() => _keepPopular = v)),
        FetchOption('つながり',
            value: _keepEdges,
            onChanged: (v) => setState(() {
                  _keepEdges = v;
                  if (v) _keepPopular = true;
                })),
      ],
      // 時間は対象の表にある。容量は記録する内容で変わるのでここに出す
      summary: e.items > 0
          ? Text('保存 ${ScanEstimate.roughBytesLabel(e.totalBytes(popular: _keepPopular, edges: _keepEdges))}')
          : null,
      onStart: count <= 0
          ? null
          : () => Navigator.pop(context, (
                origin: _chosen.origin,
                record: BlockScanRecord(
                    keepPopular: _keepPopular, keepEdges: _keepEdges),
              )),
    );
  }
}
