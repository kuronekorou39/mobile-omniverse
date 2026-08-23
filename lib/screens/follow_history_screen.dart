import 'package:flutter/material.dart';

import '../models/sns_service.dart';
import '../services/follow_db.dart';
import 'follow_snapshot_screen.dart';

/// 取得履歴の全件。
///
/// 対象の画面には直近だけ出し、溜まった分はこちらで見せる。
/// 多い対象では 40 件近くになるので、1 画面に全部並べると
/// ダッシュボードや設定が押し流されてしまう。
class FollowHistoryScreen extends StatefulWidget {
  const FollowHistoryScreen(
      {super.key, required this.service, required this.handle});

  final SnsService service;
  final String handle;

  @override
  State<FollowHistoryScreen> createState() => _FollowHistoryScreenState();
}

class _FollowHistoryScreenState extends State<FollowHistoryScreen> {
  List<FollowSnapshot> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await FollowDb.instance.listSnapshots(
        service: widget.service, targetHandle: widget.handle, limit: 500);
    if (!mounted) return;
    setState(() {
      _history = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('@${widget.handle} の履歴')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _history.isEmpty
                ? const Center(
                    child: Text('まだ取得していません',
                        style: TextStyle(color: Colors.grey)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (_, i) => followHistoryTile(
                        _history[i],
                        onTap: () => _open(_history[i]),
                      ),
                    ),
                  ),
      );

  Future<void> _open(FollowSnapshot s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FollowSnapshotScreen(snapshot: s),
    ));
    await _load();
  }
}

/// 履歴の 1 行。対象の画面（直近だけ）と履歴の全件で同じ見た目にする
Widget followHistoryTile(FollowSnapshot s, {VoidCallback? onTap}) => ListTile(
      dense: true,
      leading: Icon(
        s.kind == 'followers'
            ? Icons.group_outlined
            : Icons.person_add_alt_outlined,
        // 完了 / 再開できる / それ以外 を色で分ける
        color: s.isCompleted
            ? Colors.green
            : (s.isResumable ? Colors.orange : Colors.red),
        size: 20,
      ),
      title: Text('${dateLabel(s.startedAt)}  ${s.collectedCount}件',
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '${s.kind == 'followers' ? 'フォロワー' : 'フォロー'}'
        '${durationLabel(s) == null ? '' : ' ・ 所要${durationLabel(s)}'}'
        '${s.isCompleted ? '' : ' ・ ${statusLabel(s)}'}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
