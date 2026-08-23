import 'package:flutter/material.dart';

import '../models/follow_user.dart';
import '../models/sns_service.dart';
import '../services/follow_db.dart';
import '../widgets/follow_list_controls.dart';
import 'follow_relation_diff_screen.dart';
import 'follow_snapshot_screen.dart';

/// 相互 / 片思われ / 片思い を見る画面。
///
/// 「同じ1回の走査で取った2本」である必要はなく、
/// **最新の完了済みフォロワー一覧と最新の完了済みフォロー一覧**を突き合わせる。
/// 取得日時がずれている場合があるので、両方の日時を画面に出す。
class FollowRelationScreen extends StatefulWidget {
  const FollowRelationScreen(
      {super.key, required this.service, required this.handle});

  final SnsService service;
  final String handle;

  @override
  State<FollowRelationScreen> createState() => _FollowRelationScreenState();
}

/// タブと、対応する relationMembers の onlyIn
const _tabs = <({String label, String? onlyIn, String empty})>[
  (label: '相互', onlyIn: null, empty: '相互フォローはいません'),
  (label: '片思われ', onlyIn: 'followers', empty: '片思われはいません'),
  (label: '片思い', onlyIn: 'following', empty: '片思いはいません'),
];

class _FollowRelationScreenState extends State<FollowRelationScreen>
    with SingleTickerProviderStateMixin {
  FollowSnapshot? _followers;
  FollowSnapshot? _following;
  ({int mutual, int onlyFollowers, int onlyFollowing})? _counts;
  FollowFilter _filter = FollowFilter.none;
  FollowSort _sort = FollowSort.initial;
  bool _loading = true;

  /// 比較ボタンは「今見ているタブ」に効かせるので、index を自分で持つ
  late final TabController _tab =
      TabController(length: _tabs.length, vsync: this)
        ..addListener(() {
          if (mounted) setState(() {});
        });

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = FollowDb.instance;
    final f =
        await db.latestCompleted(widget.service, widget.handle, 'followers');
    final g =
        await db.latestCompleted(widget.service, widget.handle, 'following');
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

  /// 完了済みのフォロワーとフォローを新しい順に組にする。
  ///
  /// 相互はスナップショットとして保存していないので、「N 回前の相互」は
  /// (N 回前のフォロワー, N 回前のフォロー) から作り直すしかない。
  /// 両方を続けて取る運用を想定して、新しい順に単純に突き合わせる。
  Future<List<({FollowSnapshot followers, FollowSnapshot following})>>
      _generations() async {
    final db = FollowDb.instance;
    Future<List<FollowSnapshot>> completed(String kind) async =>
        (await db.listSnapshots(
                service: widget.service,
                targetHandle: widget.handle,
                kind: kind))
            .where((s) => s.isCompleted && s.collectedCount > 0)
            .toList();

    final followers = await completed('followers');
    final following = await completed('following');
    final pairs = <({FollowSnapshot followers, FollowSnapshot following})>[];
    for (var i = 0; i < followers.length && i < following.length; i++) {
      pairs.add((followers: followers[i], following: following[i]));
    }
    return pairs;
  }

  Future<void> _openDiff() async {
    final generations = await _generations();
    if (!mounted) return;

    // 先頭が今表示している世代。比べる相手はそれより古いもの
    if (generations.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('比較するには、フォロワーとフォローの両方を 2 回以上取る必要があります')),
      );
      return;
    }

    final current = generations.first;
    final older = await showModalBottomSheet<
        ({FollowSnapshot followers, FollowSnapshot following})>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('比較する世代を選ぶ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final g in generations.skip(1))
              ListTile(
                title: Text(dateLabel(g.followers.startedAt)),
                subtitle: Text(
                  'フォロワー ${g.followers.collectedCount}件'
                  ' ／ フォロー ${g.following.collectedCount}件'
                  '（${dateLabel(g.following.startedAt)}）',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.pop(ctx, g),
              ),
          ],
        ),
      ),
    );
    if (older == null || !mounted) return;

    final tab = _tabs[_tab.index];
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FollowRelationDiffScreen(
        handle: widget.handle,
        label: tab.label,
        onlyIn: tab.onlyIn,
        olderFollowers: older.followers,
        olderFollowing: older.following,
        newerFollowers: current.followers,
        newerFollowing: current.following,
      ),
    ));
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

    final counts = [c?.mutual, c?.onlyFollowers, c?.onlyFollowing];

    return Scaffold(
      appBar: AppBar(
        title: Text('@${widget.handle} の関係'),
        actions: [
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: '${_tabs[_tab.index].label}を過去と比較する',
            onPressed: _openDiff,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: [
            for (var i = 0; i < _tabs.length; i++)
              Tab(
                  text: counts[i] == null
                      ? _tabs[i].label
                      : '${_tabs[i].label} (${counts[i]})'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Text(
              'フォロワー ${dateLabel(f.startedAt)}（${f.collectedCount}件）'
              ' ／ フォロー ${dateLabel(g.startedAt)}（${g.collectedCount}件）',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
          FollowListControls(
            filter: _filter,
            sort: _sort,
            showProtected: f.service == SnsService.x,
            onChanged: (filter, sort) =>
                setState(() => (_filter = filter, _sort = sort)),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [for (final t in _tabs) _list(f, g, t.onlyIn, t.empty)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
          FollowSnapshot f, FollowSnapshot g, String? onlyIn, String empty) =>
      PagedFollowList<FollowUser>(
        reloadKey: (onlyIn, _filter, _sort),
        fetch: (offset, limit) => FollowDb.instance.relationMembers(
          followersSnapshotId: f.id,
          followingSnapshotId: g.id,
          onlyIn: onlyIn,
          filter: _filter,
          sort: _sort,
          limit: limit,
          offset: offset,
        ),
        itemBuilder: (u) => FollowUserTile(
            user: u, service: f.service, accountId: f.sessionAccountId),
        emptyLabel: empty,
      );
}
