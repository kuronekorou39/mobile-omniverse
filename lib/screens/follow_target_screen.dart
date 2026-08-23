import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import '../services/follow_capture_engine.dart';
import '../services/follow_capture_job_service.dart';
import '../services/follow_db.dart';
import '../utils/app_snackbar.dart';
import '../utils/confirm_dialog.dart';
import '../utils/image_headers.dart';
import 'follow_relation_screen.dart';
import 'follow_snapshot_screen.dart';

/// 走査対象 1 件の詳細。情報量が多いので 概要 / 履歴 / 設定 の 3 タブに分ける。
class FollowTargetScreen extends StatefulWidget {
  const FollowTargetScreen(
      {super.key, required this.service, required this.handle});

  final SnsService service;
  final String handle;

  @override
  State<FollowTargetScreen> createState() => _FollowTargetScreenState();
}

class _FollowTargetScreenState extends State<FollowTargetScreen> {
  static const _intervalChoices = [0, 1, 3, 7];

  final _job = FollowCaptureJobService.instance;

  FollowTarget? _target;
  FollowSnapshot? _latestFollowers;
  FollowSnapshot? _latestFollowing;
  ({int mutual, int onlyFollowers, int onlyFollowing})? _relation;
  List<FollowSnapshot> _history = [];
  int _sizeBytes = 0;
  final Map<String, DateTime?> _nextDue = {};
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
    final target = await db.getTarget(widget.service, widget.handle) ??
        await _registerOwnAccount();
    final f =
        await db.latestCompleted(widget.service, widget.handle, 'followers');
    final g =
        await db.latestCompleted(widget.service, widget.handle, 'following');
    final relation = (f == null || g == null)
        ? null
        : await db.relationCounts(
            followersSnapshotId: f.id, followingSnapshotId: g.id);
    final history = await db.listSnapshots(
        service: widget.service, targetHandle: widget.handle);

    final total = await db.databaseSizeBytes();
    final rows = await db.memberRowsByTarget();
    final all = rows.values.fold<int>(0, (a, b) => a + b);
    final mine = rows[(service: widget.service, handle: widget.handle)] ?? 0;

    if (target != null) {
      for (final kind in const ['followers', 'following']) {
        _nextDue[kind] =
            await FollowCaptureJobService.nextDueAt(target, kind);
      }
    }

    if (!mounted) return;
    setState(() {
      _target = target;
      _latestFollowers = f;
      _latestFollowing = g;
      _relation = relation;
      _history = history;
      _sizeBytes = all == 0 ? 0 : (total * mine / all).round();
      _loading = false;
    });
  }

  /// この画面はアカウント一覧からも開ける。まだ対象として登録していない
  /// 自分のアカウントなら、ここで登録してしまう。
  ///
  /// 登録せずに null のままにすると、読み込み中の表示から先に進めない。
  /// 対象にできるのは自分のアカウントだけ (他人の @ID はハブ画面から追加する)。
  Future<FollowTarget?> _registerOwnAccount() async {
    final account = AccountStorageService.instance.accounts
        .where((a) =>
            a.service == widget.service &&
            a.handle.replaceFirst('@', '').toLowerCase() == widget.handle)
        .firstOrNull;
    if (account == null) return null;

    final target = FollowTarget(
      service: account.service,
      handle: widget.handle,
      displayName: account.displayName,
      avatarUrl: account.avatarUrl ?? '',
      sessionAccountId: account.id,
      addedAt: DateTime.now(),
    );
    await FollowDb.instance.upsertTarget(target);
    await _job.markAutoRegistered(account.id);
    return target;
  }

  /// 実行アカウントの候補。対象と同じ SNS のものしか使えない
  List<Account> get _usableAccounts => AccountStorageService.instance.accounts
      .where((a) => a.service == widget.service)
      .toList();

  Account? get _sessionAccount {
    final id = _target?.sessionAccountId;
    final accounts = _usableAccounts;
    if (accounts.isEmpty) return null;
    return accounts.firstWhere((a) => a.id == id, orElse: () => accounts.first);
  }

  @override
  Widget build(BuildContext context) {
    final t = _target;
    if (_loading || t == null) {
      return Scaffold(
        appBar: AppBar(title: Text('@${widget.handle}')),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              // 回り続けるスピナーで止まらないよう、理由を出して抜けられるようにする
              : const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'この対象はまだ登録されていません。\n'
                    'フォロー / フォロワー取得の画面から追加してください。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
        ),
      );
    }

    final running = _job.progress.value;
    final isMine = running?.targetHandle == widget.handle &&
        running?.service == widget.service;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(children: [
            _avatar(t),
            const SizedBox(width: 8),
            Expanded(
              child: Text('@${t.handle}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18)),
            ),
          ]),
          bottom: const TabBar(tabs: [
            Tab(text: '概要'),
            Tab(text: '履歴'),
            Tab(text: '設定'),
          ]),
        ),
        body: Column(
          children: [
            if (isMine) _runningCard(running!),
            Expanded(
              child: TabBarView(children: [
                _overviewTab(),
                _historyTab(),
                _settingsTab(t),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 概要 ───

  Widget _overviewTab() => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            _summaryRow('フォロワー', _latestFollowers),
            _summaryRow('フォロー', _latestFollowing),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(_relation == null
                  ? '相互 — 両方の取得が必要'
                  : '相互 ${_relation!.mutual}'),
              subtitle: _relation == null
                  ? null
                  : Text(
                      '片思われ ${_relation!.onlyFollowers} ・ '
                      '片思い ${_relation!.onlyFollowing}',
                      style: const TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FollowRelationScreen(
                    service: widget.service, handle: widget.handle),
              )),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('今すぐ取得'),
              enabled: !_job.isRunning,
              onTap: _pickKind,
            ),
            for (final s in _history.where((s) => s.isResumable))
              ListTile(
                leading: const Icon(Icons.play_arrow, color: Colors.orange),
                title: Text(
                    '${s.kind == 'followers' ? 'フォロワー' : 'フォロー'}の続きから再開'),
                subtitle: Text('${s.collectedCount}件まで取得済み',
                    style: const TextStyle(fontSize: 11)),
                enabled: !_job.isRunning,
                onTap: () => _start(
                    s.kind == 'followers'
                        ? FollowListKind.followers
                        : FollowListKind.following,
                    resume: s),
              ),
            const SizedBox(height: 32),
          ],
        ),
      );

  Widget _summaryRow(String label, FollowSnapshot? s) => ListTile(
        leading: Icon(label == 'フォロワー'
            ? Icons.group_outlined
            : Icons.person_add_alt_outlined),
        title: Text(s == null ? '$label — 未取得' : '$label ${s.collectedCount}件'),
        subtitle: s == null
            ? null
            : Text(
                '${dateLabel(s.startedAt)}'
                '${durationLabel(s) == null ? '' : ' ・ 所要${durationLabel(s)}'}'
                '${looksIncomplete(s) ? ' ・ 取りこぼしの可能性' : ''}',
                style: TextStyle(
                    fontSize: 11,
                    color: looksIncomplete(s) ? Colors.orange : null)),
        trailing: s == null ? null : const Icon(Icons.chevron_right),
        onTap: s == null ? null : () => _openSnapshot(s),
      );

  // ─── 履歴 ───

  Widget _historyTab() {
    if (_history.isEmpty) {
      return const Center(
          child: Text('まだ取得していません', style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _history.length,
        itemBuilder: (_, i) {
          final s = _history[i];
          return ListTile(
            dense: true,
            leading: Icon(
              s.kind == 'followers'
                  ? Icons.group_outlined
                  : Icons.person_add_alt_outlined,
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
            onTap: () => _openSnapshot(s),
          );
        },
      ),
    );
  }

  // ─── 設定 ───

  Widget _settingsTab(FollowTarget t) => ListView(
        children: [
          _header('実行アカウント'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'X の鍵アカウントは、つながっているアカウントでないと取得できません',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(_sessionAccount?.handle ?? 'なし'),
            trailing: DropdownButton<String>(
              value: _sessionAccount?.id,
              underline: const SizedBox.shrink(),
              items: [
                for (final a in _usableAccounts)
                  DropdownMenuItem(value: a.id, child: Text(a.handle)),
              ],
              onChanged: _job.isRunning
                  ? null
                  : (v) => _updateTarget(t.copyWith(sessionAccountId: v)),
            ),
          ),
          const Divider(),
          _header('定期取得'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '前回の完了から指定日数が過ぎていれば、次の起動時に1回だけ実行します',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          _intervalPicker('フォロワー', 'followers', t.followersIntervalDays,
              (v) => _updateTarget(t.copyWith(followersIntervalDays: v))),
          _intervalPicker('フォロー', 'following', t.followingIntervalDays,
              (v) => _updateTarget(t.copyWith(followingIntervalDays: v))),
          const Divider(),
          _header('保存容量'),
          _sizeBar(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('この対象と履歴を削除',
                style: TextStyle(color: Colors.red)),
            onTap: _confirmDelete,
          ),
          const SizedBox(height: 32),
        ],
      );

  Widget _intervalPicker(
          String label, String kind, int value, ValueChanged<int> onChanged) =>
      ListTile(
        dense: true,
        title: Text(label),
        subtitle: value <= 0
            ? null
            : Text(_nextDueLabel(kind),
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: DropdownButton<int>(
          value: _intervalChoices.contains(value) ? value : 0,
          underline: const SizedBox.shrink(),
          items: [
            for (final d in _intervalChoices)
              DropdownMenuItem(value: d, child: Text(d == 0 ? 'なし' : '$d日おき')),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      );

  String _nextDueLabel(String kind) {
    final due = _nextDue[kind];
    if (due == null) return '次回: 未定';
    if (!due.isAfter(DateTime.now())) return '次回: 次の起動時';
    return '次回: ${dateLabel(due)}';
  }

  Widget _sizeBar() {
    final limit = _job.sizeLimitBytes;
    final ratio = limit == 0 ? 0.0 : (_sizeBytes / limit).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: ratio, minHeight: 6),
          const SizedBox(height: 4),
          Text(
            '${formatBytes(_sizeBytes)} / 全体上限 ${formatBytes(limit)}（概算）',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ─── 共通パーツ ───

  Widget _avatar(FollowTarget t) => ClipOval(
        child: t.avatarUrl.isEmpty
            ? const SizedBox(width: 28, height: 28, child: Icon(Icons.person))
            : CachedNetworkImage(
                imageUrl: t.avatarUrl,
                httpHeaders: kImageHeaders,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                memCacheWidth: 56,
                errorWidget: (_, __, ___) => const SizedBox(
                    width: 28, height: 28, child: Icon(Icons.person)),
              ),
      );

  Widget _runningCard(FollowJobProgress p) {
    final rate = p.rateLimit;
    final waitLeft = p.waitingUntil?.difference(DateTime.now());
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                    '${p.kind == FollowListKind.followers ? 'フォロワー' : 'フォロー'}'
                    '${p.cancelling ? 'の取得を中断しています…' : 'を取得中'}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: p.cancelling ? null : _job.cancel,
                child: const Text('中断'),
              ),
            ]),
            Text('${p.collected} 件 / ${p.round} ページ',
                style: const TextStyle(fontSize: 20)),
            Text(
              [
                if (rate?.remaining != null)
                  'レート残 ${rate!.remaining}/${rate.limit ?? '?'}',
                '経過 ${elapsedLabel(DateTime.now().difference(p.startedAt))}',
              ].join(' ・ '),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            // 高さを固定して、出入りで下がずれないようにする
            SizedBox(
              height: 16,
              width: double.infinity,
              child: p.waitingReason == null
                  ? null
                  : Text(
                      '待機中: ${p.waitingReason}'
                      '${waitLeft == null || waitLeft.isNegative ? '' : '（あと${waitLeft.inSeconds}秒）'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.orange),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            )),
      );

  // ─── 操作 ───

  Future<void> _openSnapshot(FollowSnapshot s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FollowSnapshotScreen(snapshot: s),
    ));
    await _load();
  }

  Future<void> _updateTarget(FollowTarget updated) async {
    await FollowDb.instance.upsertTarget(updated);
    if (mounted) setState(() => _target = updated);
  }

  Future<void> _start(FollowListKind kind, {FollowSnapshot? resume}) async {
    final account = _sessionAccount;
    if (account == null) {
      showAppSnackBar(context, '実行アカウントがありません', type: SnackType.error);
      return;
    }
    try {
      final result = await _job.run(
        account: account,
        targetHandle: widget.handle,
        kind: kind,
        resume: resume,
      );
      if (mounted) {
        showAppSnackBar(
            context,
            result?.isCompleted == false
                ? '中断しました（続きから再開できます）'
                : '取得が終了しました');
      }
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e', type: SnackType.error);
    }
    await _load();
  }

  Future<void> _startBoth() async {
    final account = _sessionAccount;
    if (account == null) return;
    try {
      await _job.runBoth(account: account, targetHandle: widget.handle);
      if (mounted) showAppSnackBar(context, '取得が終了しました');
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e', type: SnackType.error);
    }
    await _load();
  }

  Future<void> _pickKind() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('フォロワーを取得'),
            onTap: () => Navigator.pop(context, 'followers'),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_outlined),
            title: const Text('フォローを取得'),
            onTap: () => Navigator.pop(context, 'following'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('両方を続けて取得'),
            subtitle: const Text('相互を出すにはこちら'),
            onTap: () => Navigator.pop(context, 'both'),
          ),
        ]),
      ),
    );
    if (choice == null) return;
    if (choice == 'both') return _startBoth();
    await _start(choice == 'followers'
        ? FollowListKind.followers
        : FollowListKind.following);
  }

  Future<void> _confirmDelete() async {
    final ok = await confirmDialog(
      context,
      title: '@${widget.handle} を削除',
      message: 'この対象の履歴とデータをすべて削除します。元に戻せません。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok) return;
    try {
      await FollowDb.instance.deleteTarget(widget.service, widget.handle);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, '削除に失敗しました: $e', type: SnackType.error);
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
