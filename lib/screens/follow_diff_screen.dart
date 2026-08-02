import 'package:flutter/material.dart';

import '../models/follow_user.dart';
import '../services/follow_db.dart';
import 'follow_snapshot_screen.dart';

/// 2 つの走査結果の差分。
/// フォロワーなら「増えた = 新規フォロワー」「減った = フォロー解除」になる。
class FollowDiffScreen extends StatefulWidget {
  const FollowDiffScreen({super.key, required this.older, required this.newer});

  final FollowSnapshot older;
  final FollowSnapshot newer;

  @override
  State<FollowDiffScreen> createState() => _FollowDiffScreenState();
}

class _FollowDiffScreenState extends State<FollowDiffScreen> {
  List<FollowUser> _added = [];
  List<FollowUser> _removed = [];
  List<FollowCountChange> _changes = [];
  bool _loading = true;

  bool get _isFollowers => widget.newer.kind == 'followers';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await FollowDb.instance.diff(
      oldSnapshotId: widget.older.id,
      newSnapshotId: widget.newer.id,
    );
    final changes = await FollowDb.instance.countChanges(
      oldSnapshotId: widget.older.id,
      newSnapshotId: widget.newer.id,
    );
    if (!mounted) return;
    setState(() {
      _added = d.added;
      _removed = d.removed;
      _changes = changes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final addedLabel = _isFollowers ? '増えた（新規フォロワー）' : '増えた（フォローした）';
    final removedLabel = _isFollowers ? '減った（フォロー解除）' : '減った（フォロー外した）';

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('@${widget.newer.targetHandle} の差分'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '$addedLabel ${_loading ? '' : '(${_added.length})'}'),
              Tab(text: '$removedLabel ${_loading ? '' : '(${_removed.length})'}'),
              Tab(text: '件数の変化 ${_loading ? '' : '(${_changes.length})'}'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${_dateLabel(widget.older.startedAt)}（${widget.older.collectedCount}件）'
                ' → ${_dateLabel(widget.newer.startedAt)}（${widget.newer.collectedCount}件）',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
            if (!widget.older.isCompleted || !widget.newer.isCompleted)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '⚠ 途中で終わった走査が含まれています。差分は不正確です。',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _list(_added, Icons.add_circle, Colors.green),
                        _list(_removed, Icons.remove_circle, Colors.red),
                        _changeList(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 両方に居る人の、ツイート数とフォロワー数の増減
  Widget _changeList() {
    if (_changes.isEmpty) {
      return const Center(
          child: Text('件数の変化はありません\n（v1 のデータには記録がありません）',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _changes.length,
      itemBuilder: (_, i) {
        final c = _changes[i];
        return FollowUserTile(
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
        );
      },
    );
  }

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

  Widget _list(List<FollowUser> users, IconData icon, Color color) {
    if (users.isEmpty) {
      return const Center(
          child: Text('変化なし', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (_, i) => FollowUserTile(
        user: users[i],
        leadingIcon: Icon(icon, color: color),
        accountId: widget.newer.sessionAccountId,
      ),
    );
  }

  static String _dateLabel(DateTime dt) =>
      '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
