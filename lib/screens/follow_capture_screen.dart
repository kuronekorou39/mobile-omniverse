import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import '../services/follow_capture_job_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/follow_db.dart';
import '../services/x_api_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/image_headers.dart';
import '../widgets/sns_badge.dart';
import 'follow_snapshot_screen.dart' show dateLabel;
import 'follow_target_screen.dart';

/// フォロー/フォロワー取得のハブ。走査対象の一覧と全体設定を置く。
class FollowCaptureScreen extends StatefulWidget {
  const FollowCaptureScreen({super.key});

  @override
  State<FollowCaptureScreen> createState() => _FollowCaptureScreenState();
}

class _FollowCaptureScreenState extends State<FollowCaptureScreen> {
  final _job = FollowCaptureJobService.instance;

  List<FollowTarget> _targets = [];
  final Map<FollowTargetKey, _TargetSummary> _summaries = {};
  int _totalBytes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _job.progress.addListener(_onProgress);
    _load();
  }

  @override
  void dispose() {
    _job.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final db = FollowDb.instance;
    await _job.loadSettings();
    await _ensureOwnAccountsRegistered();

    final targets = await db.listTargets();
    final total = await db.databaseSizeBytes();
    final rows = await db.memberRowsByTarget();
    final allRows = rows.values.fold<int>(0, (a, b) => a + b);

    final summaries = <FollowTargetKey, _TargetSummary>{};
    for (final t in targets) {
      final f = await db.latestCompleted(t.service, t.handle, 'followers');
      final g = await db.latestCompleted(t.service, t.handle, 'following');
      final relation = (f == null || g == null)
          ? null
          : await db.relationCounts(
              followersSnapshotId: f.id, followingSnapshotId: g.id);
      summaries[t.key] = _TargetSummary(
        followers: f,
        following: g,
        mutual: relation?.mutual,
        bytes:
            allRows == 0 ? 0 : (total * (rows[t.key] ?? 0) / allRows).round(),
      );
    }

    if (!mounted) return;
    setState(() {
      _targets = targets;
      _summaries
        ..clear()
        ..addAll(summaries);
      _totalBytes = total;
      _loading = false;
    });
  }

  /// ログイン済みの自分のアカウントは、対象として自動登録しておく。
  ///
  /// 登録するのは **アカウントにつき一度だけ**。毎回入れ直すと、
  /// ユーザーが対象を削除しても次にこの画面を開いた瞬間に復活してしまい、
  /// 「削除しても消えない」ように見える。消したい人は消せるようにする。
  ///
  /// 既にある対象は、表示名やアイコンが欠けていれば補完する。
  /// v3 マイグレーションで既存スナップショットから復元した行には
  /// handle しか入っていないため。
  Future<void> _ensureOwnAccountsRegistered() async {
    final db = FollowDb.instance;
    for (final a in _accounts) {
      final handle = a.handle.replaceFirst('@', '').toLowerCase();
      final existing = await db.getTarget(a.service, handle);
      if (existing == null) {
        if (_job.isAutoRegistered(a.id)) continue; // 削除済み → 復活させない
        await db.upsertTarget(FollowTarget(
          service: a.service,
          handle: handle,
          displayName: a.displayName,
          avatarUrl: a.avatarUrl ?? '',
          sessionAccountId: a.id,
          addedAt: DateTime.now(),
        ));
      } else if (existing.avatarUrl.isEmpty || existing.displayName.isEmpty) {
        await db.upsertTarget(existing.copyWith(
          displayName: existing.displayName.isEmpty ? a.displayName : null,
          avatarUrl: existing.avatarUrl.isEmpty ? (a.avatarUrl ?? '') : null,
          sessionAccountId: existing.sessionAccountId ?? a.id,
        ));
      }
      await _job.markAutoRegistered(a.id);
    }
  }

  /// 対象にできるのはログイン済みのアカウントがある SNS だけ。
  /// X も Bluesky も同じ一覧に並べる
  List<Account> get _accounts => AccountStorageService.instance.accounts;

  @override
  Widget build(BuildContext context) {
    final running = _job.progress.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('フォロー / フォロワー取得'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '設定',
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '対象を追加',
        onPressed: _accounts.isEmpty ? null : _addTarget,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  _storageBar(),
                  if (running != null) _runningBanner(running),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      '他の画面に移っても取得は続きます。中断しても続きから再開できます。',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('予定分を今すぐ実行'),
                    subtitle: const Text('中断分の再開と、期限が来た定期取得',
                        style: TextStyle(fontSize: 11)),
                    enabled: !_job.isRunning,
                    onTap: _runDueNow,
                  ),
                  const Divider(),
                  if (_targets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('対象がありません。＋ から追加してください',
                          style: TextStyle(color: Colors.grey)),
                    )
                  else
                    for (final t in _targets) _targetTile(t, running),
                  const SizedBox(height: 80),
                ],
              ),
      ),
    );
  }

  Widget _storageBar() {
    final limit = _job.sizeLimitBytes;
    final ratio = limit == 0 ? 0.0 : (_totalBytes / limit).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: ratio, minHeight: 8),
          const SizedBox(height: 4),
          Text(
            '${formatBytes(_totalBytes)} / ${formatBytes(limit)}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _runningBanner(FollowJobProgress p) => Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: ListTile(
          leading: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text(p.cancelling
              ? '@${p.targetHandle} を中断しています…'
              : '@${p.targetHandle} を取得中'),
          subtitle: Text('${p.collected}件 / ${p.round}ページ',
              style: const TextStyle(fontSize: 11)),
          trailing: TextButton(
            onPressed: p.cancelling ? null : _job.cancel,
            child: const Text('中断'),
          ),
          onTap: () => _openTarget(p.service, p.targetHandle),
        ),
      );

  Widget _targetTile(FollowTarget t, FollowJobProgress? running) {
    final s = _summaries[t.key];
    final isRunning = running?.targetHandle == t.handle &&
        running?.service == t.service;
    final schedule = [
      if (t.followersIntervalDays > 0) 'フォロワー${t.followersIntervalDays}日',
      if (t.followingIntervalDays > 0) 'フォロー${t.followingIntervalDays}日',
    ].join(' / ');

    return ListTile(
      // SNS はアイコンの左に置く。@ID の右だと ID の長さで位置が動いて
      // 縦に並べたときに揃わない
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SnsBadge(service: t.service, size: 9),
          const SizedBox(width: 8),
          ClipOval(
            child: t.avatarUrl.isEmpty
                ? const SizedBox(
                    width: 40, height: 40, child: Icon(Icons.person))
                : CachedNetworkImage(
                    imageUrl: t.avatarUrl,
                    httpHeaders: kImageHeaders,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    memCacheWidth: 80,
                    errorWidget: (_, __, ___) => const SizedBox(
                        width: 40, height: 40, child: Icon(Icons.person)),
                  ),
          ),
        ],
      ),
      title: Text('@${t.handle}', overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          s?.followers == null
              ? 'フォロワー —'
              : 'フォロワー ${s!.followers!.collectedCount}',
          s?.following == null
              ? 'フォロー —'
              : 'フォロー ${s!.following!.collectedCount}',
          if (s?.mutual != null) '相互 ${s!.mutual}',
        ].join(' / ') +
            (s?.lastLabel == null ? '' : '\n最終 ${s!.lastLabel}') +
            (schedule.isEmpty ? '' : ' ・ $schedule'),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: isRunning
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right),
      onTap: () => _openTarget(t.service, t.handle),
    );
  }

  Future<void> _runDueNow() async {
    try {
      await _job.runDueWork(accounts: _accounts, force: true);
      if (mounted) showAppSnackBar(context, '期日の取得が終わりました');
    } catch (e) {
      if (mounted) showAppSnackBar(context, '\$e', type: SnackType.error);
    }
    await _load();
  }

  Future<void> _openTarget(SnsService service, String handle) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FollowTargetScreen(service: service, handle: handle),
    ));
    await _load();
  }

  /// 任意の @ID を対象に追加する。実在確認を兼ねてプロフィールを引く
  Future<void> _addTarget() async {
    final controller = TextEditingController();
    var accountId = _accounts.first.id;

    final handle = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('対象を追加'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixText: '@',
                  hintText: 'screen_name',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(labelText: '実行アカウント'),
                items: [
                  for (final a in _accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SnsBadge(service: a.service, size: 9),
                          const SizedBox(width: 6),
                          Text(a.handle),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setLocal(() => accountId = v ?? accountId),
              ),
              const SizedBox(height: 8),
              const Text(
                '選んだアカウントと同じ SNS の対象になります。\n'
                'X の鍵アカウントは、つながっているアカウントを選んでください',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('追加')),
          ],
        ),
      ),
    );

    if (handle == null || handle.isEmpty) return;
    final normalized = handle.replaceFirst('@', '').toLowerCase();
    final account = _accounts.firstWhere((a) => a.id == accountId);

    showAppSnackBar(context, '@$normalized を確認しています…');
    final target = account.service == SnsService.bluesky
        ? await _lookupBlueskyTarget(account, normalized)
        : await _lookupXTarget(account, normalized);

    if (!mounted) return;
    if (target == null) {
      showAppSnackBar(context, '@$normalized が見つかりませんでした',
          type: SnackType.error);
      return;
    }

    await FollowDb.instance.upsertTarget(target);
    await _load();
    if (mounted) showAppSnackBar(context, '@${target.handle} を追加しました');
  }

  /// 実在確認を兼ねてプロフィールを引き、表示名とアイコンを控える
  Future<FollowTarget?> _lookupXTarget(Account account, String handle) async {
    Map<String, dynamic>? profile;
    try {
      profile = await XApiService.instance
          .getUserProfile(account.xCredentials, handle);
    } catch (_) {}
    if (profile == null) return null;

    final legacy = profile['legacy'] as Map<String, dynamic>? ?? const {};
    final core = profile['core'] as Map<String, dynamic>? ?? const {};
    return FollowTarget(
      service: SnsService.x,
      handle: handle,
      displayName: (core['name'] ?? legacy['name'] ?? '') as String,
      avatarUrl: (legacy['profile_image_url_https'] ?? '') as String,
      restId: profile['rest_id'] as String?,
      sessionAccountId: account.id,
      addedAt: DateTime.now(),
    );
  }

  Future<FollowTarget?> _lookupBlueskyTarget(
      Account account, String handle) async {
    Map<String, dynamic>? profile;
    try {
      profile = await BlueskyApiService.instance
          .getProfile(account.blueskyCredentials, handle);
    } catch (_) {}
    if (profile == null) return null;

    return FollowTarget(
      service: SnsService.bluesky,
      // 入力が DID でも handle でも引けるので、返ってきた handle を採る
      handle: (profile['handle'] as String?)?.toLowerCase() ?? handle,
      displayName: (profile['displayName'] as String?) ?? '',
      avatarUrl: (profile['avatar'] as String?) ?? '',
      restId: profile['did'] as String?,
      sessionAccountId: account.id,
      addedAt: DateTime.now(),
    );
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('取得の設定',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SwitchListTile(
                title: const Text('起動時に自動実行'),
                subtitle: const Text('中断分の再開と、期限が来た定期取得を1件だけ',
                    style: TextStyle(fontSize: 11)),
                value: _job.autoRunOnLaunch,
                onChanged: (v) async {
                  await _job.setAutoRunOnLaunch(v);
                  setLocal(() {});
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                title: const Text('保持サイズの上限'),
                subtitle: const Text('超えたら古い履歴から削除（各対象2件は残す）',
                    style: TextStyle(fontSize: 11)),
                trailing: DropdownButton<int>(
                  value: _job.sizeLimitBytes,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final b in FollowCaptureJobService.sizeLimitChoices)
                      DropdownMenuItem(
                          value: b, child: Text(formatBytes(b))),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await _job.setSizeLimitBytes(v);
                    setLocal(() {});
                    await _load();
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetSummary {
  const _TargetSummary({
    this.followers,
    this.following,
    this.mutual,
    this.bytes = 0,
  });

  final FollowSnapshot? followers;
  final FollowSnapshot? following;
  final int? mutual;
  final int bytes;

  String? get lastLabel {
    final dates = [followers?.startedAt, following?.startedAt]
        .whereType<DateTime>()
        .toList()
      ..sort();
    return dates.isEmpty ? null : dateLabel(dates.last);
  }
}
