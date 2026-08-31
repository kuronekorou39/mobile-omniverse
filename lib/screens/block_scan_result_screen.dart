import 'package:flutter/material.dart';

import '../models/sns_service.dart';
import '../services/follow_db.dart';
import '../widgets/follow_list_controls.dart';
import 'follow_snapshot_screen.dart';

/// ブロック調査の結果。
///
/// 走査は数時間かかるので、**途中でも見られる**ことを前提にしている。
/// 集計はそのつど数え直すので、走査中に開いても今までの分が出る。
class BlockScanResultScreen extends StatefulWidget {
  const BlockScanResultScreen({super.key, required this.run});

  final BlockRun run;

  @override
  State<BlockScanResultScreen> createState() => _BlockScanResultScreenState();
}

/// タブと、対応する block_findings の列
const _tabs = <({String label, String? relation, String empty})>[
  (
    label: 'ブロックされてる',
    relation: 'blockedBy',
    empty: 'ブロックされている相手は見つかっていません'
  ),
  (label: 'ブロックしてる', relation: 'blocking', empty: 'ブロックしている相手は居ません'),
  (label: 'ミュート', relation: 'muting', empty: 'ミュートしている相手は居ません'),
  // relation なしは「人気」。関係ではなく被フォロー数で並べる
  (label: '人気', relation: null, empty: 'まだ集まっていません'),
];

class _BlockScanResultScreenState extends State<BlockScanResultScreen> {
  BlockRunProgress? _stats;
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

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final s = _stats;

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('@${run.targetHandle} のブロック調査'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '数え直す',
              onPressed: _load,
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: _tabLabel(0, s?.blockedBy)),
              Tab(text: _tabLabel(1, s?.blocking)),
              Tab(text: _tabLabel(2, s?.muting)),
              Tab(text: _tabs[3].label),
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
                  for (var i = 0; i < _tabs.length; i++) _list(i),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tabLabel(int i, int? count) =>
      count == null ? _tabs[i].label : '${_tabs[i].label} ($count)';

  Widget _header(BlockRun run, BlockRunProgress? s) {
    final line = s == null
        ? '集計中…'
        : '起点 ${run.originLabel} ・ '
            '${s.doneSources}/${s.totalSources}人 走査済み'
            '${s.skippedSources > 0 ? '（${s.skippedSources}人は対象外）' : ''}'
            ' ・ 延べ${s.scanned}件';

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
                color: run.isCompleted ? Colors.grey : Colors.orange),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _list(int index) {
    final tab = _tabs[index];
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
                  Text('${f.sourceCount}人',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  const Text('から',
                      style: TextStyle(fontSize: 9, color: Colors.grey)),
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
