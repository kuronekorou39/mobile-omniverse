import 'package:flutter/material.dart';

import '../models/follow_user.dart';
import '../models/sns_service.dart';
import '../services/follow_db.dart';
import '../widgets/follow_list_controls.dart';
import 'follow_snapshot_screen.dart';

/// 相互 / 片思われ / 片思い を世代どうしで比べる画面。
///
/// フォロワーやフォローと違い、相互はスナップショットとして保存していない。
/// そのつど「フォロワー ∩ フォロー」で出しているので、比べるには
/// (フォロワー, フォロー) の組を 2 世代ぶん渡して、両方の集合を作り直す。
class FollowRelationDiffScreen extends StatefulWidget {
  const FollowRelationDiffScreen({
    super.key,
    required this.handle,
    required this.label,
    required this.onlyIn,
    required this.olderFollowers,
    required this.olderFollowing,
    required this.newerFollowers,
    required this.newerFollowing,
  });

  final String handle;

  /// 「相互」「片思われ」「片思い」。画面の見出しに出す
  final String label;

  /// [FollowDb.relationDiffMembers] に渡す種別
  final String? onlyIn;

  final FollowSnapshot olderFollowers;
  final FollowSnapshot olderFollowing;
  final FollowSnapshot newerFollowers;
  final FollowSnapshot newerFollowing;

  @override
  State<FollowRelationDiffScreen> createState() =>
      _FollowRelationDiffScreenState();
}

class _FollowRelationDiffScreenState extends State<FollowRelationDiffScreen> {
  int? _added;
  int? _removed;
  FollowFilter _filter = FollowFilter.none;
  FollowSort _sort = FollowSort.initial;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final counts = await FollowDb.instance.relationDiffCounts(
      oldFollowersId: widget.olderFollowers.id,
      oldFollowingId: widget.olderFollowing.id,
      newFollowersId: widget.newerFollowers.id,
      newFollowingId: widget.newerFollowing.id,
      onlyIn: widget.onlyIn,
    );
    if (!mounted) return;
    setState(() {
      _added = counts.added;
      _removed = counts.removed;
    });
  }

  String _tabLabel(String label, int? count) =>
      count == null ? label : '$label ($count)';

  @override
  Widget build(BuildContext context) {
    final service = widget.newerFollowers.service;
    final incomplete = [
      widget.olderFollowers,
      widget.olderFollowing,
      widget.newerFollowers,
      widget.newerFollowing,
    ].any((s) => !s.isCompleted);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('@${widget.handle} の${widget.label}の差分'),
          bottom: TabBar(tabs: [
            Tab(text: _tabLabel('増えた', _added)),
            Tab(text: _tabLabel('減った', _removed)),
          ]),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Text(
                '${dateLabel(widget.olderFollowers.startedAt)}'
                ' → ${dateLabel(widget.newerFollowers.startedAt)}'
                '${incomplete ? '\n⚠ 中断した取得を含むため、差分は不正確です' : ''}',
                style: TextStyle(
                    fontSize: 11,
                    color: incomplete ? Colors.orange : Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
            FollowListControls(
              filter: _filter,
              sort: _sort,
              showProtected: service == SnsService.x,
              onChanged: (filter, sort) =>
                  setState(() => (_filter = filter, _sort = sort)),
            ),
            Expanded(
              child: TabBarView(children: [
                _list(added: true),
                _list(added: false),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list({required bool added}) => PagedFollowList<FollowUser>(
        reloadKey: (added, _filter, _sort),
        fetch: (offset, limit) => FollowDb.instance.relationDiffMembers(
          oldFollowersId: widget.olderFollowers.id,
          oldFollowingId: widget.olderFollowing.id,
          newFollowersId: widget.newerFollowers.id,
          newFollowingId: widget.newerFollowing.id,
          onlyIn: widget.onlyIn,
          added: added,
          filter: _filter,
          sort: _sort,
          limit: limit,
          offset: offset,
        ),
        itemBuilder: (u) => FollowUserTile(
          user: u,
          service: widget.newerFollowers.service,
          leadingIcon: Icon(added ? Icons.add_circle : Icons.remove_circle,
              color: added ? Colors.green : Colors.red),
          accountId: widget.newerFollowers.sessionAccountId,
        ),
        emptyLabel: added
            ? '${widget.label}になった人はいません'
            : '${widget.label}でなくなった人はいません',
      );
}
