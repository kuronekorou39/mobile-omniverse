import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sns_service.dart';
import '../services/block_scan_service.dart';
import '../services/export_service.dart';
import '../services/follow_db.dart';
import '../utils/number_format.dart';
import '../utils/app_snackbar.dart';
import '../utils/confirm_dialog.dart';
import '../widgets/follow_list_controls.dart';
import 'follow_snapshot_screen.dart';

/// つながり調査の結果。
///
/// 走査は数時間かかるので、**途中でも見られる**ことを前提にしている。
/// 集計はそのつど数え直すので、走査中に開いても今までの分が出る。
class BlockScanResultScreen extends StatefulWidget {
  const BlockScanResultScreen({super.key, required this.run});

  final BlockRun run;

  @override
  State<BlockScanResultScreen> createState() => _BlockScanResultScreenState();
}

typedef _Tab = ({String label, String? relation, String empty});

/// タブと、対応する block_findings の列
const _tabs = <_Tab>[
  (
    label: '被ブロック',
    relation: 'blockedBy',
    empty: 'ブロックされている相手は見つかっていません'
  ),
  (label: 'ブロック中', relation: 'blocking', empty: 'ブロックしている相手は居ません'),
  (label: 'ミュート中', relation: 'muting', empty: 'ミュートしている相手は居ません'),
  // relation なしは「人気」。関係ではなく被フォロー数で並べる
  (label: '人気', relation: null, empty: 'まだ集まっていません'),
];

class _BlockScanResultScreenState extends State<BlockScanResultScreen> {
  BlockRunProgress? _stats;

  /// 記録していない関係と、フォロー先を残していない調査の「人気」は、
  /// 元データが無いのでタブごと出さない
  late final List<_Tab> _visibleTabs = [
    for (final t in _tabs)
      if (t.relation == null
          ? widget.run.keepEdges
          : widget.run.relations.contains(t.relation))
        t,
  ];
  FollowFilter _filter = FollowFilter.none;

  /// 人気タブで「自分がフォローしていない相手」だけに絞るか
  bool _onlyNotFollowed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await FollowDb.instance.blockRunProgress(widget.run.id);
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  bool _exporting = false;

  /// 数万件になることがあるので、書き出し中はボタンを止めて待たせる
  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await ExportService.instance.blockRunCsv(widget.run);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '@${widget.run.targetHandle} のつながり調査',
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, '書き出しに失敗しました: $e', type: SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _confirmDelete() async {
    final run = widget.run;
    final s = _stats;
    final ok = await confirmDialog(
      context,
      title: 'この調査を削除',
      message: '${run.originLabel}起点の調査'
          '${s == null ? '' : '（${formatNumber(s.doneSources)}/${formatNumber(s.totalSources)}人ぶん）'}'
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
      if (mounted) {
        showAppSnackBar(context, '削除に失敗しました: $e', type: SnackType.error);
      }
      return;
    }
    if (!mounted) return;
    showAppSnackBar(context, '調査を削除しました');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final s = _stats;

    return DefaultTabController(
      length: _visibleTabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('@${run.targetHandle} のつながり調査'),
          actions: [
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'CSV で書き出す',
              onPressed: _exporting ? null : _export,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '数え直す',
              onPressed: _load,
            ),
            // 調査は GB 単位になるので、消す手段は必ず出しておく。
            // 押し間違えないよう、アイコンでは並べずメニューに畳む
            PopupMenuButton<void>(
              itemBuilder: (_) => [
                PopupMenuItem(
                  // 走っている最中に消すと、走査が書き込み先を失う
                  enabled: !BlockScanService.instance.isRunning,
                  onTap: _confirmDelete,
                  child: const Text('この調査を削除'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final t in _visibleTabs) Tab(text: _tabLabel(t, s)),
            ],
          ),
        ),
        body: Column(
          children: [
            _header(run, s),
            FollowListControls(
              filter: _filter,
              sort: FollowSort.initial,
              showSort: false, // 並びは「見つかった人数の多い順」で固定
              onChanged: (filter, _) => setState(() => _filter = filter),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (var i = 0; i < _visibleTabs.length; i++) _list(i),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tabLabel(_Tab t, BlockRunProgress? s) {
    final count = switch (t.relation) {
      'blockedBy' => s?.blockedBy,
      'blocking' => s?.blocking,
      'muting' => s?.muting,
      _ => null,
    };
    return count == null ? t.label : '${t.label} ($count)';
  }

  Widget _header(BlockRun run, BlockRunProgress? s) {
    final scheme = Theme.of(context).colorScheme;
    // 1 行に全部並べると画面幅で変な所から折り返す。
    // 走査の進みと、集めた量とで行を分ける
    final line = s == null
        ? '集計中…'
        : '起点 ${run.originLabel} ・ '
            '${formatNumber(s.doneSources)}/${formatNumber(s.totalSources)}人 走査済み'
            '${s.skippedSources > 0 ? '（${formatNumber(s.skippedSources)}人は対象外）' : ''}'
            '\n延べ${formatNumber(s.scanned)}件'
            '${run.recordLabel == null ? '' : ' ・ 記録: ${run.recordLabel}'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          if (s != null && s.totalSources > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(minHeight: 3, value: s.ratio),
            ),
          const SizedBox(height: 4),
          Text(
            '$line\n${dateLabel(run.startedAt)}'
            '${run.isCompleted ? '' : ' ・ 未完了（途中までの結果です）'}',
            style: TextStyle(
                fontSize: 11,
                color: run.isCompleted
                    ? scheme.onSurfaceVariant
                    : scheme.tertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _list(int index) {
    final scheme = Theme.of(context).colorScheme;
    final tab = _visibleTabs[index];
    final isPopular = tab.relation == null;

    return Column(
      children: [
        if (isPopular)
          SwitchListTile(
            dense: true,
            value: _onlyNotFollowed,
            onChanged: (v) => setState(() => _onlyNotFollowed = v),
            title: const Text('自分がフォローしていない相手だけ',
                style: TextStyle(fontSize: 12)),
          ),
        Expanded(
          child: PagedFollowList<BlockFinding>(
            reloadKey: (index, _filter, _onlyNotFollowed),
            fetch: (offset, limit) => isPopular
                ? FollowDb.instance.popularAmongSources(
                    runId: widget.run.id,
                    onlyNotFollowed: _onlyNotFollowed,
                    limit: limit,
                    offset: offset,
                  )
                : FollowDb.instance.blockFindings(
                    runId: widget.run.id,
                    relation: tab.relation!,
                    filter: _filter,
                    limit: limit,
                    offset: offset,
                  ),
            itemBuilder: (f) => FollowUserTile(
              user: f.user,
              service: SnsService.x,
              accountId: widget.run.sessionAccountId,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${formatNumber(f.sourceCount)}人',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  Text('から',
                      style: TextStyle(
                          fontSize: 9, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            emptyLabel: tab.empty,
          ),
        ),
      ],
    );
  }
}
