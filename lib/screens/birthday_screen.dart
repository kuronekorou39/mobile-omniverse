import 'package:flutter/material.dart';

import '../models/sns_service.dart';
import '../services/follow_db.dart';
import '../utils/number_format.dart';
import '../widgets/skeleton.dart';
import 'follow_snapshot_screen.dart';

/// 誕生日が分かっている人を、月ごとに並べる。
///
/// 今月から始めて 1 年ぶん回す。「次に誰の誕生日が来るか」が知りたいことで、
/// 1 月から並べると今が 12 月のとき一番下まで送ることになる
class BirthdayScreen extends StatefulWidget {
  const BirthdayScreen({super.key, required this.service, required this.handle});

  final SnsService service;
  final String handle;

  @override
  State<BirthdayScreen> createState() => _BirthdayScreenState();
}

/// [from] 月から始めて 12 か月ぶん
List<int> monthsStartingFrom(int from) =>
    [for (var i = 0; i < 12; i++) (from - 1 + i) % 12 + 1];

/// 誕生年が分かれば満年齢。今年の誕生日が来ていなければ 1 引く
int? ageOf({required int? year, required int month, required int day, DateTime? now}) {
  if (year == null) return null;
  final t = now ?? DateTime.now();
  var age = t.year - year;
  if (t.month < month || (t.month == month && t.day < day)) age--;
  return age < 0 ? null : age;
}

class _BirthdayScreenState extends State<BirthdayScreen> {
  String _origin = 'all';
  FollowSnapshot? _followers;
  FollowSnapshot? _following;
  List<BirthdayEntry>? _entries;
  DetailCoverage? _coverage;

  static const _origins = <({String key, String label})>[
    (key: 'all', label: 'すべて'),
    (key: 'following', label: 'フォロー'),
    (key: 'followers', label: 'フォロワー'),
    (key: 'mutual', label: '相互'),
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
    final entries = m == null ? <BirthdayEntry>[] : await db.birthdays(m);
    final coverage = m == null ? null : await db.detailCoverage(m);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _coverage = coverage;
    });
  }

  void _setOrigin(String key) {
    setState(() {
      _origin = key;
      _entries = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _coverage;
    return Scaffold(
      appBar: AppBar(
        title: Text('@${widget.handle} の誕生日'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              c == null
                  ? ' '
                  : '誕生日が分かる ${formatNumber(c.birthdayKnown)}人 ・ '
                      '調べた ${formatNumber(c.profileFetched)}人 / ${formatNumber(c.total)}人',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _originChips(),
          Expanded(child: _entries == null ? _skeleton() : _list(_entries!)),
        ],
      ),
    );
  }

  Widget _originChips() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            for (final o in _origins) ...[
              ChoiceChip(
                label: Text(o.label),
                selected: _origin == o.key,
                onSelected: (_) => _setOrigin(o.key),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      );

  Widget _list(List<BirthdayEntry> entries) {
    final scheme = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            (_coverage?.profileFetched ?? 0) == 0
                ? 'まだ調べていません。対象の画面の「詳しい情報」から取得できます'
                : '誕生日を公開している人が居ません',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final byMonth = <int, List<BirthdayEntry>>{};
    for (final e in entries) {
      (byMonth[e.month] ??= []).add(e);
    }
    final months = monthsStartingFrom(now.month)
        .where((m) => byMonth.containsKey(m))
        .toList();

    return ListView.builder(
      itemCount: months.length,
      itemBuilder: (_, i) {
        final m = months[i];
        final list = byMonth[m]!;
        final isThisMonth = m == now.month;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Text('$m月',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isThisMonth
                              ? scheme.primary
                              : scheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Text('${list.length}人',
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                  if (isThisMonth) ...[
                    const SizedBox(width: 8),
                    Text('今月',
                        style:
                            TextStyle(fontSize: 11, color: scheme.primary)),
                  ],
                ],
              ),
            ),
            for (final e in list)
              FollowUserTile(
                user: e.user,
                service: widget.service,
                accountId: _following?.sessionAccountId ??
                    _followers?.sessionAccountId,
                trailing: _dayBadge(e, now),
              ),
          ],
        );
      },
    );
  }

  /// 右端に日付。今日なら色を付ける。年が分かれば年齢も
  Widget _dayBadge(BirthdayEntry e, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final today = e.month == now.month && e.day == now.day;
    final age = ageOf(year: e.year, month: e.month, day: e.day, now: now);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${e.month}/${e.day}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: today ? scheme.primary : scheme.onSurface,
          ),
        ),
        Text(
          today ? '今日' : (age == null ? '' : '$age歳'),
          style: TextStyle(
              fontSize: 10,
              color: today ? scheme.primary : scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _skeleton() =>
      SkeletonList(itemBuilder: (i) => UserTileSkeleton(variant: i));
}
