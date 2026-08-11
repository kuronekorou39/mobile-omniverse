import 'package:flutter/material.dart';

import '../models/follow_user.dart';
import '../services/follow_db.dart';
import 'follow_snapshot_screen.dart';

/// 相互 / 片思われ / 片思い を見る画面。
///
/// 「同じ1回の走査で取った2本」である必要はなく、
/// **最新の完了済みフォロワー一覧と最新の完了済みフォロー一覧**を突き合わせる。
/// 取得日時がずれている場合があるので、両方の日時を画面に出す。
class FollowRelationScreen extends StatefulWidget {
  const FollowRelationScreen({super.key, required this.handle});

  final String handle;

  @override
  State<FollowRelationScreen> createState() => _FollowRelationScreenState();
}

class _FollowRelationScreenState extends State<FollowRelationScreen> {
  FollowSnapshot? _followers;
  FollowSnapshot? _following;
  ({int mutual, int onlyFollowers, int onlyFollowing})? _counts;
  FollowSortOrder _sort = FollowSortOrder.followersDesc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = FollowDb.instance;
    final f = await db.latestCompleted(widget.handle, 'followers');
    final g = await db.latestCompleted(widget.handle, 'following');
    final counts = (f == null || g == null)
        ? null
        : await db.relationCounts(
            followersSnapshotId: f.id, followingSnapshotId: g.id);
    if (!mounted) return;
    setState(() {
      _followers = f;
      _following = g;
      _counts = counts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _followers, g = _following;
    final c = _counts;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('@${widget.handle} の関係')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (f == null || g == null) {
      return Scaffold(
        appBar: AppBar(title: Text('@${widget.handle} の関係')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '相互を出すには、フォロワーとフォローの両方が必要です。\n\n'
              'フォロワー ${f == null ? "未取得" : "取得済み"}'
              ' ／ フォロー ${g == null ? "未取得" : "取得済み"}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('@${widget.handle} の関係'),
          actions: [
            PopupMenuButton<FollowSortOrder>(
              icon: const Icon(Icons.sort),
              tooltip: '並び順',
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => [
                for (final o in FollowSortOrder.values)
                  PopupMenuItem(value: o, child: Text(o.label)),
              ],
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: '相互${c == null ? '' : ' (${c.mutual})'}'),
              Tab(text: '片思われ${c == null ? '' : ' (${c.onlyFollowers})'}'),
              Tab(text: '片思い${c == null ? '' : ' (${c.onlyFollowing})'}'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'フォロワー ${dateLabel(f.startedAt)}（${f.collectedCount}件）'
                ' ／ フォロー ${dateLabel(g.startedAt)}（${g.collectedCount}件）',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _list(f, g, null, '相互フォローはいません'),
                  _list(f, g, 'followers', '片思われはいません'),
                  _list(f, g, 'following', '片思いはいません'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(
          FollowSnapshot f, FollowSnapshot g, String? onlyIn, String empty) =>
      PagedFollowList<FollowUser>(
        reloadKey: (onlyIn, _sort),
        fetch: (offset, limit) => FollowDb.instance.relationMembers(
          followersSnapshotId: f.id,
          followingSnapshotId: g.id,
          onlyIn: onlyIn,
          sort: _sort,
          limit: limit,
          offset: offset,
        ),
        itemBuilder: (u) =>
            FollowUserTile(user: u, accountId: f.sessionAccountId),
        emptyLabel: empty,
      );
}
