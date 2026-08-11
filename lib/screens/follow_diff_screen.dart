import 'package:flutter/material.dart';

import '../models/follow_user.dart';
import '../services/follow_db.dart';
import 'follow_snapshot_screen.dart';

/// 2 回分の取得結果の差分。
/// フォロワーなら「増えた = 新規フォロワー」「減った = フォロー解除」になる。
///
/// 件数だけ先に数えてタブに出し、中身は 3 つとも [PagedFollowList] で
/// 順に読む。対象が数万人だと差分も数万件になりうるため、上限は設けない。
class FollowDiffScreen extends StatefulWidget {
  const FollowDiffScreen({super.key, required this.older, required this.newer});

  final FollowSnapshot older;
  final FollowSnapshot newer;

  @override
  State<FollowDiffScreen> createState() => _FollowDiffScreenState();
}

class _FollowDiffScreenState extends State<FollowDiffScreen> {
  int? _added;
  int? _removed;
  int? _changed;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final db = FollowDb.instance;
    final oldId = widget.older.id, newId = widget.newer.id;
    final diff =
        await db.diffCounts(oldSnapshotId: oldId, newSnapshotId: newId);
    final changed =
        await db.countChangesTotal(oldSnapshotId: oldId, newSnapshotId: newId);
    if (!mounted) return;
    setState(() {
      _added = diff.added;
      _removed = diff.removed;
      _changed = changed;
    });
  }

  String _tab(String label, int? count) =>
      count == null ? label : '$label ($count)';

  @override
  Widget build(BuildContext context) {
    final o = widget.older, n = widget.newer;
    final incomplete = !o.isCompleted || !n.isCompleted;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('@${n.targetHandle} の差分'),
          bottom: TabBar(tabs: [
            Tab(text: _tab('増えた', _added)),
            Tab(text: _tab('減った', _removed)),
            Tab(text: _tab('変化', _changed)),
          ]),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '${dateLabel(o.startedAt)}（${o.collectedCount}件）'
                ' → ${dateLabel(n.startedAt)}（${n.collectedCount}件）'
                '${incomplete ? '\n⚠ 中断した取得を含むため、差分は不正確です' : ''}',
                style: TextStyle(
                    fontSize: 11,
                    color: incomplete ? Colors.orange : Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: TabBarView(children: [
                _memberList(added: true),
                _memberList(added: false),
                _changeList(),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberList({required bool added}) => PagedFollowList<FollowUser>(
        fetch: (offset, limit) => FollowDb.instance.diffMembers(
          oldSnapshotId: widget.older.id,
          newSnapshotId: widget.newer.id,
          added: added,
          limit: limit,
          offset: offset,
        ),
        itemBuilder: (u) => FollowUserTile(
          user: u,
          leadingIcon: Icon(added ? Icons.add_circle : Icons.remove_circle,
              color: added ? Colors.green : Colors.red),
          accountId: widget.newer.sessionAccountId,
        ),
        emptyLabel: added ? '増えた人はいません' : '減った人はいません',
      );

  /// 両方に居る人の、ツイート数とフォロワー数の増減
  Widget _changeList() => PagedFollowList<FollowCountChange>(
        fetch: (offset, limit) => FollowDb.instance.countChanges(
          oldSnapshotId: widget.older.id,
          newSnapshotId: widget.newer.id,
          limit: limit,
          offset: offset,
        ),
        itemBuilder: (c) => FollowUserTile(
          user: c.user,
          accountId: widget.newer.sessionAccountId,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _delta('ツイート', c.statusesDelta),
              _delta('フォロワー', c.followersDelta),
            ],
          ),
        ),
        emptyLabel: '件数の変化はありません',
      );

  Widget _delta(String label, int? value) {
    if (value == null || value == 0) {
      return Text('$label —',
          style: const TextStyle(fontSize: 10, color: Colors.grey));
    }
    final up = value > 0;
    return Text(
      '$label ${up ? '+' : ''}$value',
      style: TextStyle(
        fontSize: 10,
        color: up ? Colors.green : Colors.red,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
