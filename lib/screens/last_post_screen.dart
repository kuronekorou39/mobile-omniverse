import 'package:flutter/material.dart';

import '../models/sns_service.dart';
import '../services/follow_db.dart';
import '../utils/number_format.dart';
import '../utils/relative_time.dart';
import 'follow_snapshot_screen.dart';

/// 最近の投稿日を調べた人を、古い順に並べる。
///
/// 知りたいのは「誰が止まっているか」なので、投稿が見つからなかった人を
/// 先頭に、あとは最後の投稿が古い順。期間で絞れる
class LastPostScreen extends StatefulWidget {
  const LastPostScreen({super.key, required this.service, required this.handle});

  final SnsService service;
  final String handle;

  @override
  State<LastPostScreen> createState() => _LastPostScreenState();
}

class _LastPostScreenState extends State<LastPostScreen> {
  String _origin = 'all';

  /// 何日以上投稿が無い人に絞るか。null なら全員
  int? _olderThanDays;
  FollowSnapshot? _followers;
  FollowSnapshot? _following;
  MemberSet? _members;
  DetailCoverage? _coverage;
  bool _loading = true;

  static const _origins = <({String key, String label})>[
    (key: 'all', label: 'すべて'),
    (key: 'following', label: 'フォロー'),
    (key: 'followers', label: 'フォロワー'),
    (key: 'mutual', label: '相互'),
  ];

  static const _periods = <({int? days, String label})>[
    (days: null, label: '全員'),
    (days: 30, label: '30日以上'),
    (days: 90, label: '90日以上'),
    (days: 365, label: '1年以上'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = FollowDb.instance;
    _followers ??=
        await db.latestCompleted(widget.service, widget.handle, 'followers');
    _following ??=
        await db.latestCompleted(widget.service, widget.handle, 'following');
    final m = FollowDb.memberSetFor(_origin,
        followers: _followers, following: _following);
    final coverage = m == null ? null : await db.detailCoverage(m);
    if (!mounted) return;
    setState(() {
      _members = m;
      _coverage = coverage;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _coverage;
    final m = _members;
    final cutoff = _olderThanDays == null
        ? null
        : DateTime.now()
            .subtract(Duration(days: _olderThanDays!))
            .millisecondsSinceEpoch;
    return Scaffold(
      appBar: AppBar(
        title: Text('@${widget.handle} の最近の投稿日'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              c == null
                  ? ' '
                  : '調べた ${formatNumber(c.postsFetched)}人 / ${formatNumber(c.total)}人',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _chips(
            [for (final o in _origins) (o.key, o.label)],
            selected: _origin,
            onPick: (k) {
              setState(() {
                _origin = k;
                _loading = true;
              });
              _load();
            },
          ),
          _chips(
            [for (final p in _periods) ('${p.days}', '${p.label}${p.days == null ? '' : '投稿なし'}')],
            selected: '$_olderThanDays',
            onPick: (k) => setState(
                () => _olderThanDays = k == 'null' ? null : int.parse(k)),
          ),
          Expanded(
            child: _loading || m == null
                ? m == null && !_loading
                    ? Center(
                        child: Text('一覧がありません',
                            style: TextStyle(
                                fontSize: 13, color: scheme.onSurfaceVariant)))
                    : const SizedBox.shrink()
                : PagedFollowList<LastPostEntry>(
                    reloadKey: (_origin, _olderThanDays),
                    fetch: (offset, limit) => FollowDb.instance.lastPosts(
                      m,
                      olderThanMs: cutoff,
                      limit: limit,
                      offset: offset,
                    ),
                    itemBuilder: (e) => FollowUserTile(
                      user: e.user,
                      service: widget.service,
                      accountId: _following?.sessionAccountId ??
                          _followers?.sessionAccountId,
                      trailing: _ago(e.detail),
                    ),
                    emptyLabel: (c?.postsFetched ?? 0) == 0
                        ? 'まだ調べていません。対象の画面の「詳しい情報」から取得できます'
                        : '該当なし',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chips(List<(String, String)> items,
          {required String selected, required void Function(String) onPick}) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        child: Row(
          children: [
            for (final (key, label) in items) ...[
              ChoiceChip(
                label: Text(label),
                selected: selected == key,
                onSelected: (_) => onPick(key),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      );

  /// 右端に「最後の投稿がいつか」。リポストしか無い人はそれも添える
  Widget _ago(UserDetail d) {
    final scheme = Theme.of(context).colorScheme;
    final last = d.lastPostAt;
    final own = d.lastOwnPostAt;
    if (last == null) {
      return Text(
        d.error != null ? '取得できず' : '投稿なし',
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: d.error != null ? scheme.outline : scheme.tertiary),
      );
    }
    final stale = DateTime.now().difference(last).inDays >= 90;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(agoLabel(last),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: stale ? scheme.tertiary : scheme.onSurface)),
        Text(
          own == null
              ? 'リポストのみ'
              : own == last
                  ? '自分の投稿'
                  : '自分の投稿 ${agoLabel(own)}',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
