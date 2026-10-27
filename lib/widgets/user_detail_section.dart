import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../screens/birthday_screen.dart';
import '../screens/last_post_screen.dart';
import '../services/fetch_jobs.dart';
import '../services/follow_db.dart';
import '../services/scan_estimate.dart';
import '../services/user_detail_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/number_format.dart';
import 'fetch_busy_note.dart';
import 'follow_section_header.dart';
import 'skeleton.dart';

/// 対象画面に置く「詳しい情報」のひとかたまり。
///
/// 一覧の API に載らない誕生日と最近の投稿日を、1 人ずつ取りに行く。
/// 1 人 1 回ずつ通信するので小さな一覧向け。何人を調べるかと、
/// どれくらいかかるかを見せてから始める
class UserDetailSection extends StatefulWidget {
  const UserDetailSection({
    super.key,
    required this.service,
    required this.handle,
    required this.account,
  });

  final SnsService service;
  final String handle;

  /// 通信に使うアカウント。null なら始められない
  final Account? account;

  @override
  State<UserDetailSection> createState() => _UserDetailSectionState();
}

class _UserDetailSectionState extends State<UserDetailSection> {
  final _svc = UserDetailService.instance;

  FollowSnapshot? _followers;
  FollowSnapshot? _following;
  DetailCoverage? _coverage;
  bool _loading = true;

  bool? _expanded;
  static const _prefExpanded = 'user_detail_section_expanded';

  @override
  void initState() {
    super.initState();
    _svc.progress.addListener(_onProgress);
    FetchJobs.instance.current.addListener(_onBusyChanged);
    _load();
  }

  @override
  void dispose() {
    _svc.progress.removeListener(_onProgress);
    FetchJobs.instance.current.removeListener(_onBusyChanged);
    super.dispose();
  }

  void _onBusyChanged() {
    if (mounted) setState(() {});
  }

  void _onProgress() {
    if (!mounted) return;
    // 終わったら調べた人数を読み直す
    if (_svc.progress.value == null) {
      _load();
    } else {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final db = FollowDb.instance;
    final followers =
        await db.latestCompleted(widget.service, widget.handle, 'followers');
    final following =
        await db.latestCompleted(widget.service, widget.handle, 'following');
    final all = FollowDb.memberSetFor('all',
        followers: followers, following: following);
    final coverage = all == null ? null : await db.detailCoverage(all);
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _followers = followers;
      _following = following;
      _coverage = coverage;
      _expanded = prefs.getBool(_prefExpanded);
      _loading = false;
    });
  }

  bool get _isMine => _svc.progress.value?.targetHandle == widget.handle;

  @override
  Widget build(BuildContext context) {
    // 誕生日は X にしか無く、投稿一覧の取り方も X 向けにしか書いていない
    if (widget.service != SnsService.x) return const SizedBox.shrink();

    final running = _svc.progress.value;
    final isMine = running != null && _isMine;
    // 別の対象の取得も、フォロー/フォロワー取得やつながり調査も、
    // 走っている間はここから始められない
    final blockedBy = isMine ? null : FetchJobs.instance.current.value;
    final c = _coverage;
    final hasData = c != null && (c.profileFetched > 0 || c.postsFetched > 0);
    final open = _expanded ?? (isMine || hasData);

    return Padding(
      padding: const EdgeInsets.only(bottom: FollowSectionHeader.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FollowSectionHeader(
            '詳しい情報',
            info: '一覧には載らない誕生日と最近の投稿日を、1 人ずつプロフィールと'
                '投稿を見て集めます。1 人につき 1〜2 回通信するので、'
                '数千人までの一覧向けです。\n'
                '誕生日は本人が公開している範囲だけ分かります（年だけ非公開の人も居ます）。'
                '最近の投稿日は、投稿一覧の 1 ページ目から読みます。\n'
                '一度調べた人は ${UserDetailService.freshFor.inDays} 日間は飛ばすので、'
                '途中で止めても次に始めれば続きになります。',
            expanded: open,
            onToggle: () => _setExpanded(!open),
            summary: isMine
                ? '取得中'
                : c == null || !hasData
                    ? null
                    : '${formatNumber(c.profileFetched > c.postsFetched ? c.profileFetched : c.postsFetched)}人分',
          ),
          if (open) ..._body(running, isMine, blockedBy),
        ],
      ),
    );
  }

  Future<void> _setExpanded(bool value) async {
    setState(() => _expanded = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefExpanded, value);
  }

  List<Widget> _body(
      UserDetailProgress? running, bool isMine, RunningFetch? blockedBy) {
    final c = _coverage;
    return [
      if (isMine) _runningCard(running!),
      if (blockedBy != null) FetchBusyNote(blockedBy),
      if (_loading) ...[
        const SkeletonBox(height: 48, radius: 12),
        const SizedBox(height: 4),
        const SkeletonBox(height: 48, radius: 12),
      ] else ...[
        _linkRow(
          icon: Icons.cake_outlined,
          label: '誕生日',
          value: c == null
              ? '一覧がありません'
              : c.profileFetched == 0
                  ? '未取得'
                  : '${formatNumber(c.birthdayKnown)}人分（${formatNumber(c.profileFetched)}人を調べた）',
          onTap: c == null || c.profileFetched == 0
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BirthdayScreen(
                        service: widget.service, handle: widget.handle),
                  )),
        ),
        _linkRow(
          icon: Icons.schedule,
          label: '最近の投稿日',
          value: c == null
              ? '一覧がありません'
              : c.postsFetched == 0
                  ? '未取得'
                  : '${formatNumber(c.postsFetched)}人分',
          onTap: c == null || c.postsFetched == 0
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LastPostScreen(
                        service: widget.service, handle: widget.handle),
                  )),
        ),
      ],
      const SizedBox(height: 8),
      if (!isMine)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: widget.account != null && blockedBy == null && c != null
                ? _pickAndStart
                : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22)),
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            child: Text(blockedBy != null ? '他の取得が終わるまで待機' : '取得する'),
          ),
        ),
    ];
  }

  Widget _linkRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 0, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(label,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 18,
                color: onTap == null ? scheme.outlineVariant : scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _runningCard(UserDetailProgress p) {
    final scheme = Theme.of(context).colorScheme;
    final waitLeft = p.waitingUntil?.difference(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.cancelling ? '取得を中断しています…' : '取得中',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: p.cancelling ? null : _svc.cancel,
                child: const Text('中断'),
              ),
            ]),
            Text('${formatNumber(p.done)} / ${formatNumber(p.total)} 人',
                style: const TextStyle(fontSize: 20)),
            Text(
              waitLeft != null && !waitLeft.isNegative
                  ? '${p.waitingReason ?? '待機中'}。あと ${_waitLabel(waitLeft)}'
                  : p.currentHandle == null
                      ? '準備中'
                      : '@${p.currentHandle} を調べています'
                          '${p.failed > 0 ? '（${formatNumber(p.failed)}人は取れず）' : ''}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            if (p.total > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                    minHeight: 3, value: p.done / p.total),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _waitLabel(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes}分' : '${d.inSeconds}秒';

  // ─── 開始 ───

  Future<void> _pickAndStart() async {
    final account = widget.account;
    if (account == null) return;
    final db = FollowDb.instance;

    // 起点ごとの人数。無い一覧は選ばせない
    final origins = <({String key, String label})>[
      (key: 'following', label: 'フォロー'),
      (key: 'followers', label: 'フォロワー'),
      (key: 'mutual', label: '相互'),
    ];
    final counts = <String, int?>{};
    for (final o in origins) {
      final m = FollowDb.memberSetFor(o.key,
          followers: _followers, following: _following);
      counts[o.key] = m == null ? null : (await db.detailCoverage(m)).total;
    }
    if (!mounted) return;

    final picked = await showDialog<_StartChoice>(
      context: context,
      builder: (ctx) => _StartDialog(
        origins: origins,
        counts: counts,
        followers: _followers,
        following: _following,
      ),
    );
    if (picked == null || !mounted) return;

    try {
      final n = await _svc.start(
        account: account,
        service: widget.service,
        handle: widget.handle,
        origin: picked.origin,
        wantBirthday: picked.birthday,
        wantLastPost: picked.lastPost,
        refresh: picked.refresh,
      );
      if (!mounted) return;
      if (n == 0) showAppSnackBar(context, '調べる人が居ません（全員が取得済みです）');
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e', type: SnackType.error);
    }
    await _load();
  }
}

class _StartChoice {
  const _StartChoice({
    required this.origin,
    required this.birthday,
    required this.lastPost,
    required this.refresh,
  });
  final String origin;
  final bool birthday;
  final bool lastPost;
  final bool refresh;
}

/// 起点と項目を選び、何人・どれくらいかを見てから始める
class _StartDialog extends StatefulWidget {
  const _StartDialog({
    required this.origins,
    required this.counts,
    required this.followers,
    required this.following,
  });

  final List<({String key, String label})> origins;
  final Map<String, int?> counts;
  final FollowSnapshot? followers;
  final FollowSnapshot? following;

  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  late String _origin = widget.origins
      .firstWhere((o) => (widget.counts[o.key] ?? 0) > 0,
          orElse: () => widget.origins.first)
      .key;
  bool _birthday = true;
  bool _lastPost = true;
  bool _refresh = false;
  Future<int>? _pending;

  @override
  void initState() {
    super.initState();
    _recount();
  }

  /// 選び直すたびに「実際に調べる人数」を数え直す
  void _recount() {
    final m = FollowDb.memberSetFor(_origin,
        followers: widget.followers, following: widget.following);
    if (m == null || (!_birthday && !_lastPost)) {
      _pending = Future.value(0);
      return;
    }
    final now = DateTime.now();
    final freshAfter = _refresh
        ? now.millisecondsSinceEpoch + 1
        : now.subtract(UserDetailService.freshFor).millisecondsSinceEpoch;
    _pending = FollowDb.instance
        .detailCandidates(m,
            wantBirthday: _birthday,
            wantLastPost: _lastPost,
            freshAfterMs: freshAfter)
        .then((c) => c.length);
  }

  int get _requestsPerPerson => (_birthday ? 1 : 0) + (_lastPost ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final note = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final canStart = (widget.counts[_origin] ?? 0) > 0 && _requestsPerPerson > 0;
    return AlertDialog(
      title: const Text('詳しい情報を取得'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('誰を調べますか',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurfaceVariant)),
            RadioGroup<String>(
              groupValue: _origin,
              onChanged: (v) => setState(() {
                _origin = v ?? _origin;
                _recount();
              }),
              child: Column(
                children: [
                  for (final o in widget.origins)
                    RadioListTile<String>(
                      value: o.key,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      enabled: (widget.counts[o.key] ?? 0) > 0,
                      title: Text(o.label, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        widget.counts[o.key] == null
                            ? 'まだ取得していません'
                            : '${formatNumber(widget.counts[o.key]!)}人',
                        style: note,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('何を調べますか',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurfaceVariant)),
            CheckboxListTile(
              value: _birthday,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('誕生日', style: TextStyle(fontSize: 14)),
              subtitle: Text('プロフィールを 1 回', style: note),
              onChanged: (v) => setState(() {
                _birthday = v ?? false;
                _recount();
              }),
            ),
            CheckboxListTile(
              value: _lastPost,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('最近の投稿日', style: TextStyle(fontSize: 14)),
              subtitle: Text('投稿一覧を 1 ページ', style: note),
              onChanged: (v) => setState(() {
                _lastPost = v ?? false;
                _recount();
              }),
            ),
            SwitchListTile(
              value: _refresh,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('取得済みの人も調べ直す',
                  style: TextStyle(fontSize: 14)),
              subtitle: Text(
                  'ふだんは ${UserDetailService.freshFor.inDays} 日以内に調べた人を飛ばします',
                  style: note),
              onChanged: (v) => setState(() {
                _refresh = v;
                _recount();
              }),
            ),
            const SizedBox(height: 8),
            FutureBuilder<int>(
              future: _pending,
              builder: (ctx, snap) {
                final n = snap.data;
                if (n == null) return const SkeletonBox(height: 32, radius: 6);
                if (n == 0) {
                  return Text('調べる人が居ません', style: note);
                }
                final d = UserDetailService.defaultInterval * (n * _requestsPerPerson);
                return Text(
                  '${formatNumber(n)}人 × $_requestsPerPerson回の通信。'
                  '目安 ${ScanEstimate.roughLabel(d)}。'
                  'X の制限に当たると、その間は待つので長くなります。',
                  style: note,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: canStart
              ? () => Navigator.pop(
                    context,
                    _StartChoice(
                      origin: _origin,
                      birthday: _birthday,
                      lastPost: _lastPost,
                      refresh: _refresh,
                    ),
                  )
              : null,
          child: const Text('開始'),
        ),
      ],
    );
  }
}
