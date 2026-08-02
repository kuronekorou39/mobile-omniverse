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
              '相互を出すには、フォロワーとフォローの両方を'
              '最後まで取得しておく必要があります。\n\n'
              'フォロワー: ${f == null ? "未取得" : "取得済み"}\n'
              'フォロー: ${g == null ? "未取得" : "取得済み"}',
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
                  _RelationList(
                      followersId: f.id,
                      followingId: g.id,
                      onlyIn: null,
                      sort: _sort,
                      accountId: f.sessionAccountId,
                      emptyLabel: '相互フォローはいません'),
                  _RelationList(
                      followersId: f.id,
                      followingId: g.id,
                      onlyIn: 'followers',
                      sort: _sort,
                      accountId: f.sessionAccountId,
                      emptyLabel: '片思われはいません'),
                  _RelationList(
                      followersId: f.id,
                      followingId: g.id,
                      onlyIn: 'following',
                      sort: _sort,
                      accountId: f.sessionAccountId,
                      emptyLabel: '片思いはいません'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelationList extends StatefulWidget {
  const _RelationList({
    required this.followersId,
    required this.followingId,
    required this.onlyIn,
    required this.sort,
    required this.emptyLabel,
    this.accountId,
  });

  final int followersId;
  final int followingId;
  final String? onlyIn;
  final FollowSortOrder sort;
  final String emptyLabel;
  final String? accountId;

  @override
  State<_RelationList> createState() => _RelationListState();
}

class _RelationListState extends State<_RelationList>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 100;

  final _scroll = ScrollController();
  final _users = <FollowUser>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _reachedEnd = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void didUpdateWidget(covariant _RelationList old) {
    super.didUpdateWidget(old);
    if (old.sort != widget.sort) _loadFirst();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _reachedEnd) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<List<FollowUser>> _fetch(int offset) =>
      FollowDb.instance.relationMembers(
        followersSnapshotId: widget.followersId,
        followingSnapshotId: widget.followingId,
        onlyIn: widget.onlyIn,
        sort: widget.sort,
        limit: _pageSize,
        offset: offset,
      );

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _reachedEnd = false;
    });
    final page = await _fetch(0);
    if (!mounted) return;
    setState(() {
      _users
        ..clear()
        ..addAll(page);
      _loading = false;
      _reachedEnd = page.length < _pageSize;
    });
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final page = await _fetch(_users.length);
    if (!mounted) return;
    setState(() {
      _users.addAll(page);
      _loadingMore = false;
      _reachedEnd = page.length < _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_users.isEmpty) {
      return Center(
          child: Text(widget.emptyLabel,
              style: const TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: _users.length + (_reachedEnd ? 0 : 1),
      itemBuilder: (_, i) {
        if (i >= _users.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return FollowUserTile(user: _users[i], accountId: widget.accountId);
      },
    );
  }
}
