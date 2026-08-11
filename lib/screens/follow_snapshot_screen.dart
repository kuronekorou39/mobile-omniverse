import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/follow_user.dart';
import '../models/sns_service.dart';
import '../services/follow_db.dart';
import '../utils/image_headers.dart';
import 'follow_diff_screen.dart';
import 'user_profile_screen.dart';

/// 1 回の走査結果を一覧表示する。
/// 数千件になるのでページングで読み込む。
class FollowSnapshotScreen extends StatefulWidget {
  const FollowSnapshotScreen({super.key, required this.snapshot});

  final FollowSnapshot snapshot;

  @override
  State<FollowSnapshotScreen> createState() => _FollowSnapshotScreenState();
}

class _FollowSnapshotScreenState extends State<FollowSnapshotScreen> {
  Timer? _searchDebounce;
  String _search = '';
  FollowSortOrder _sort = FollowSortOrder.followersDesc;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _search = value);
    });
  }

  /// 比較相手を選んで差分画面へ
  Future<void> _openDiff() async {
    final s = widget.snapshot;
    final candidates = (await FollowDb.instance.listSnapshots(
      targetHandle: s.targetHandle,
      kind: s.kind,
    ))
        .where((o) => o.id != s.id && o.collectedCount > 0)
        .toList();

    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('比較できる履歴がありません')),
      );
      return;
    }

    final other = await showModalBottomSheet<FollowSnapshot>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('比較する履歴を選ぶ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final c in candidates)
              ListTile(
                title: Text(dateLabel(c.startedAt)),
                subtitle: Text('${c.collectedCount}件 ・ ${statusLabel(c)}',
                    style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (other == null || !mounted) return;

    final older = other.startedAt.isBefore(s.startedAt) ? other : s;
    final newer = other.startedAt.isBefore(s.startedAt) ? s : other;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FollowDiffScreen(older: older, newer: newer),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final kindLabel = s.kind == 'followers' ? 'フォロワー' : 'フォロー';

    return Scaffold(
      appBar: AppBar(
        title: Text('@${s.targetHandle} の$kindLabel'),
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
          IconButton(
            icon: const Icon(Icons.compare_arrows),
            tooltip: '差分を見る',
            onPressed: _openDiff,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(
              '${dateLabel(s.startedAt)} ・ ${s.collectedCount}件 ・ ${statusLabel(s)}'
              '${durationLabel(s) == null ? '' : ' ・ 所要${durationLabel(s)}'}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          if (shortfallLabel(s) != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text('取りこぼしの可能性 ・ ${shortfallLabel(s)}',
                  style: const TextStyle(fontSize: 11, color: Colors.orange)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: '@ID・名前で絞り込み',
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: PagedFollowList<FollowUser>(
              reloadKey: (_search, _sort),
              fetch: (offset, limit) => FollowDb.instance.members(
                widget.snapshot.id,
                search: _search,
                sort: _sort,
                limit: limit,
                offset: offset,
              ),
              itemBuilder: (u) => FollowUserTile(
                  user: u, accountId: widget.snapshot.sessionAccountId),
              emptyLabel: '該当なし',
            ),
          ),
        ],
      ),
    );
  }
}

/// 日時ラベル。今年なら年を省く（履歴は縦に並ぶので 1 行を短くしたい）
String dateLabel(DateTime dt) {
  final md = '${dt.month}/${dt.day} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
  return dt.year == DateTime.now().year ? md : '${dt.year}/$md';
}

/// 保存されている status は running / completed / interrupted。
/// そのまま出すと英語が画面に漏れるので、必ずこれを通す
String statusLabel(FollowSnapshot s) => switch (s.status) {
      'completed' => '完了',
      'running' => '取得中',
      _ => '中断',
    };

/// 取りこぼしの疑いがあるか（プロフィール上の件数より 2% 以上少ない）
bool looksIncomplete(FollowSnapshot s) {
  final c = s.completeness;
  return c != null && c < 0.98;
}

/// 取りこぼしの警告。疑いが無ければ null
String? shortfallLabel(FollowSnapshot s) {
  if (!looksIncomplete(s)) return null;
  return '想定 ${s.totalExpected}件 に対し ${s.collectedCount}件';
}

/// 取得にかかった時間。完了していなければ null
String? durationLabel(FollowSnapshot s) {
  final end = s.completedAt;
  if (end == null) return null;
  return elapsedLabel(end.difference(s.startedAt));
}

String elapsedLabel(Duration d) {
  if (d.inHours > 0) return '${d.inHours}時間${d.inMinutes % 60}分';
  if (d.inMinutes > 0) return '${d.inMinutes}分${d.inSeconds % 60}秒';
  return '${d.inSeconds}秒';
}

/// ページングしながらユーザーを並べるリスト。
///
/// 対象が数万人だと差分も数万件になりうるので、全件をメモリに載せず
/// [pageSize] 件ずつ足していく。一覧・関係・差分で共通に使う。
class PagedFollowList<T> extends StatefulWidget {
  const PagedFollowList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    required this.emptyLabel,
    this.pageSize = 100,
    this.reloadKey,
  });

  /// offset から limit 件を読む
  final Future<List<T>> Function(int offset, int limit) fetch;
  final Widget Function(T item) itemBuilder;
  final String emptyLabel;
  final int pageSize;

  /// 変わったら先頭から読み直す（並び順の変更など）
  final Object? reloadKey;

  @override
  State<PagedFollowList<T>> createState() => _PagedFollowListState<T>();
}

class _PagedFollowListState<T> extends State<PagedFollowList<T>>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final _items = <T>[];
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
  void didUpdateWidget(covariant PagedFollowList<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) _loadFirst();
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

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _reachedEnd = false;
    });
    final page = await widget.fetch(0, widget.pageSize);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(page);
      _loading = false;
      _reachedEnd = page.length < widget.pageSize;
    });
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final page = await widget.fetch(_items.length, widget.pageSize);
    if (!mounted) return;
    setState(() {
      _items.addAll(page);
      _loadingMore = false;
      _reachedEnd = page.length < widget.pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return Center(
          child: Text(widget.emptyLabel,
              style: const TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: _items.length + (_reachedEnd ? 0 : 1),
      itemBuilder: (_, i) => i >= _items.length
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : widget.itemBuilder(_items[i]),
    );
  }
}

/// 一覧・差分の両方で使うユーザー行
class FollowUserTile extends StatelessWidget {
  const FollowUserTile({
    super.key,
    required this.user,
    this.leadingIcon,
    this.accountId,
    this.trailing,
  });

  final FollowUser user;
  final Widget? leadingIcon;
  final Widget? trailing;

  /// プロフィール取得に使う X アカウント。無いと「アカウント情報が見つかりません」になる
  final String? accountId;

  @override
  Widget build(BuildContext context) {
    final ratio = user.followRatio;
    return ListTile(
      dense: true,
      leading: leadingIcon ??
          ClipOval(
            child: user.avatarUrl.isEmpty
                ? const SizedBox(
                    width: 36, height: 36, child: Icon(Icons.person))
                : CachedNetworkImage(
                    imageUrl: user.avatarUrl,
                    httpHeaders: kImageHeaders,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    memCacheWidth: 72,
                    fadeInDuration: Duration.zero,
                    placeholder: (_, __) => const SizedBox(width: 36, height: 36),
                    errorWidget: (_, __, ___) =>
                        const SizedBox(width: 36, height: 36, child: Icon(Icons.person)),
                  ),
          ),
      title: Row(children: [
        Flexible(
            child: Text(user.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold))),
        if (user.verified)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.verified, size: 14, color: Colors.blue),
          ),
        if (user.isProtected)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.lock, size: 12, color: Colors.grey),
          ),
      ]),
      subtitle: Text(
        '@${user.screenName}  ・  '
        'フォロワー ${_fmt(user.followersCount)} / フォロー ${_fmt(user.friendsCount)}'
        '${user.statusesCount == null ? '' : ' / ツイート ${_fmt(user.statusesCount!)}'}'
        '${ratio == null ? '' : '  F比 ${ratio.toStringAsFixed(2)}'}',
        style: const TextStyle(fontSize: 11),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          username: user.name,
          handle: '@${user.screenName}',
          service: SnsService.x,
          avatarUrl: user.avatarUrl.isEmpty ? null : user.avatarUrl,
          accountId: accountId,
        ),
      )),
    );
  }

  static String _fmt(int v) {
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}万';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}千';
    return '$v';
  }
}
