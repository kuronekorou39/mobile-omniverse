import 'package:flutter/material.dart';

import '../models/follow_user.dart';
import '../services/account_age_stats.dart';
import '../services/follow_db.dart';
import '../utils/number_format.dart';
import '../widgets/follow_section_header.dart';
import '../widgets/skeleton.dart';
import 'follow_snapshot_screen.dart';

/// 一覧の中のアカウント作成日の分布。
///
/// 年ごとの山で全体の顔ぶれ（古参が多いか、最近増えたか）を、
/// 直近の月ごとの山で「まとめて作られたアカウント」の塊を見る。
/// 棒を押すと、その期間に作られた人の一覧に進む
class AccountAgeScreen extends StatefulWidget {
  const AccountAgeScreen({super.key, required this.snapshot});

  final FollowSnapshot snapshot;

  @override
  State<AccountAgeScreen> createState() => _AccountAgeScreenState();
}

class _AccountAgeScreenState extends State<AccountAgeScreen> {
  AccountAgeStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await FollowDb.instance.memberCreatedAts(widget.snapshot.id);
    if (!mounted) return;
    setState(() => _stats = AccountAgeStats.from(rows));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final kindLabel = s.kind == 'followers' ? 'フォロワー' : 'フォロー';
    return Scaffold(
      appBar: AppBar(title: Text('@${s.targetHandle} の$kindLabelの作成日')),
      body: _stats == null ? _skeleton() : _body(_stats!),
    );
  }

  Widget _body(AccountAgeStats st) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _summary(st),
        const SizedBox(height: FollowSectionHeader.sectionGap),
        const FollowSectionHeader(
          '年ごと',
          info: 'アカウントが作られた年ごとの人数です。棒を押すと、その年に作られた人の一覧を見られます。',
        ),
        if (st.years.isEmpty)
          _note('作成日が分かる人が居ません')
        else
          _bars(
            st.years.reversed.toList(),
            maxCount: st.years.map((b) => b.count).reduce((a, b) => a > b ? a : b),
          ),
        const SizedBox(height: FollowSectionHeader.sectionGap),
        FollowSectionHeader(
          '月ごと（直近 ${AccountAgeStats.monthsShown ~/ 12} 年）',
          info: '月ごとの人数です。他の月に比べて '
              '${AccountAgeStats.spikeFactor} 倍を超えて多い月'
              '（${AccountAgeStats.spikeMinCount} 人以上）に印を付けます。'
              'まとめて作られたアカウントは、同じ月に固まって現れます。',
        ),
        if (st.hasSpike)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.flag, size: 14, color: scheme.tertiary),
                const SizedBox(width: 6),
                Text('目立って多い月があります',
                    style: TextStyle(fontSize: 12, color: scheme.tertiary)),
              ],
            ),
          ),
        _bars(
          st.months,
          maxCount: st.months.map((b) => b.count).fold(0, (a, b) => a > b ? a : b),
        ),
        if (st.unknown > 0) ...[
          const SizedBox(height: 16),
          _note('${formatNumber(st.unknown)} 人は作成日が分かりません'),
        ],
      ],
    );
  }

  Widget _note(String text) => Text(text,
      style: TextStyle(
          fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant));

  /// 一番上に、知りたいことの答えだけを 3 つ並べる
  Widget _summary(AccountAgeStats st) {
    final peak = st.peakYear;
    return Row(
      children: [
        _summaryCard(
          '直近 30 日',
          formatNumber(st.last30Days.length),
          sub: '人が新しいアカウント',
          ids: st.last30Days,
          title: '直近 30 日に作られた人',
        ),
        const SizedBox(width: 8),
        _summaryCard(
          '直近 1 年',
          formatNumber(st.lastYear.length),
          sub: '人',
          ids: st.lastYear,
          title: '直近 1 年に作られた人',
        ),
        const SizedBox(width: 8),
        _summaryCard(
          '一番多い年',
          peak == null ? '—' : '${peak.year}',
          sub: peak == null ? '' : '${formatNumber(peak.count)} 人',
          ids: peak?.restIds ?? const [],
          title: peak == null ? '' : '${peak.label}に作られた人',
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value,
      {required String sub, required List<String> ids, required String title}) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: ids.isEmpty ? null : () => _openMembers(title, ids),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 横棒のならび。ラベル・棒・人数の 3 列で、棒の長さは最大に対する比
  Widget _bars(List<AgeBucket> buckets, {required int maxCount}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final b in buckets)
            InkWell(
              onTap: b.count == 0
                  ? null
                  : () => _openMembers('${b.label}に作られた人', b.restIds),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(b.label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  b.spike ? FontWeight.bold : FontWeight.normal,
                              color: b.spike
                                  ? scheme.tertiary
                                  : scheme.onSurfaceVariant)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          height: 12,
                          child: Stack(
                            children: [
                              Container(color: scheme.surfaceContainerHighest),
                              if (maxCount > 0 && b.count > 0)
                                FractionallySizedBox(
                                  widthFactor: (b.count / maxCount).clamp(0.02, 1.0),
                                  child: Container(
                                    color: b.spike
                                        ? scheme.tertiary
                                        : scheme.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        b.count == 0 ? '—' : formatNumber(b.count),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                b.spike ? FontWeight.bold : FontWeight.normal,
                            color: b.count == 0
                                ? scheme.outline
                                : b.spike
                                    ? scheme.tertiary
                                    : scheme.onSurface),
                      ),
                    ),
                    if (b.spike)
                      Icon(Icons.flag, size: 14, color: scheme.tertiary)
                    else
                      const SizedBox(width: 14),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openMembers(String title, List<String> ids) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _MembersScreen(
          snapshot: widget.snapshot,
          title: title,
          restIds: ids,
        ),
      ));

  Widget _skeleton() => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                const Expanded(child: SkeletonBox(height: 76, radius: 16)),
              ],
            ],
          ),
          const SizedBox(height: FollowSectionHeader.sectionGap),
          const FollowSectionHeader('年ごと'),
          const SkeletonBox(height: 160, radius: 16),
          const SizedBox(height: FollowSectionHeader.sectionGap),
          const FollowSectionHeader('月ごと'),
          const SkeletonBox(height: 320, radius: 16),
        ],
      );
}

/// ある期間に作られた人の一覧。id の並びを 1 ページずつ引く
class _MembersScreen extends StatelessWidget {
  const _MembersScreen({
    required this.snapshot,
    required this.title,
    required this.restIds,
  });

  final FollowSnapshot snapshot;
  final String title;
  final List<String> restIds;

  Future<List<FollowUser>> _fetch(int offset, int limit) {
    if (offset >= restIds.length) return Future.value(const []);
    final end = (offset + limit).clamp(0, restIds.length);
    return FollowDb.instance.membersByIds(snapshot.id, restIds.sublist(offset, end));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(20),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${formatNumber(restIds.length)} 人',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
        ),
        body: PagedFollowList<FollowUser>(
          fetch: _fetch,
          itemBuilder: (u) => FollowUserTile(
            user: u,
            service: snapshot.service,
            accountId: snapshot.sessionAccountId,
          ),
          emptyLabel: '該当なし',
        ),
      );
}
