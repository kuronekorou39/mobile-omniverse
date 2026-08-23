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
import 'follow_history_screen.dart';
import 'follow_relation_screen.dart';
import 'follow_snapshot_screen.dart';

/// 走査対象 1 件の詳細。情報量が多いので 概要 / 履歴 / 設定 の 3 タブに分ける。
class FollowTargetScreen extends StatefulWidget {
  const FollowTargetScreen({
    super.key,
    required this.service,
    required this.handle,
  });

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
    final target =
        await db.getTarget(widget.service, widget.handle) ??
        await _registerOwnAccount();
    final f = await db.latestCompleted(
      widget.service,
      widget.handle,
      'followers',
    );
    final g = await db.latestCompleted(
      widget.service,
      widget.handle,
      'following',
    );
    final relation = (f == null || g == null)
        ? null
        : await db.relationCounts(
            followersSnapshotId: f.id,
            followingSnapshotId: g.id,
          );
    final history = await db.listSnapshots(
      service: widget.service,
      targetHandle: widget.handle,
    );

    final total = await db.databaseSizeBytes();
    final rows = await db.memberRowsByTarget();
    final all = rows.values.fold<int>(0, (a, b) => a + b);
    final mine = rows[(service: widget.service, handle: widget.handle)] ?? 0;

    if (target != null) {
      for (final kind in const ['followers', 'following']) {
        _nextDue[kind] = await FollowCaptureJobService.nextDueAt(target, kind);
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
        .where(
          (a) =>
              a.service == widget.service &&
              a.handle.replaceFirst('@', '').toLowerCase() == widget.handle,
        )
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
    final isMine =
        running?.targetHandle == widget.handle &&
        running?.service == widget.service;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _avatar(t),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '@${t.handle}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 走査中の表示だけはスクロールの外に置く。
          // 流れて見えなくなると中断ボタンにたどり着けない
          if (isMine) _runningCard(running!),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  _dashboard(),
                  _actionSection(t),
                  const Divider(height: 32),
                  _scheduleSection(t),
                  const Divider(height: 32),
                  _historySection(),
                  const Divider(height: 32),
                  _storageSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── ダッシュボード ───

  /// フォロワー / フォロー / 相互 を横に並べる。
  ///
  /// 相互だけ取得日時を出さないのは、2 本のスナップショットの突き合わせで
  /// 出しているため「いつ取ったか」が 1 つに定まらないから。実際
  /// フォロワーとフォローの取得日は数日ずれることがある。
  Widget _dashboard() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    // ListView の中は高さが無制限なので、stretch だけでは
    // カードが無限の高さになる。IntrinsicHeight で 3 枚のうち
    // 一番高いものに合わせて確定させる
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _snapshotCard('フォロワー', _latestFollowers)),
          const SizedBox(width: 8),
          Expanded(child: _snapshotCard('フォロー', _latestFollowing)),
          const SizedBox(width: 8),
          Expanded(child: _mutualCard()),
        ],
      ),
    ),
  );

  Widget _snapshotCard(String label, FollowSnapshot? s) {
    final warn = s != null && looksIncomplete(s);
    return _statCard(
      label: label,
      value: s == null ? '—' : _compact(s.collectedCount),
      sub: s == null ? '未取得' : (warn ? '取りこぼしの可能性' : dateLabel(s.startedAt)),
      warn: warn,
      onTap: s == null ? null : () => _openSnapshot(s),
    );
  }

  Widget _mutualCard() => _statCard(
    label: '相互',
    value: _relation == null ? '—' : _compact(_relation!.mutual),
    // 未取得でも押させる。遷移先が「何が足りないか」を出す
    sub: _relation == null ? '両方が必要' : '内訳を見る',
    onTap: () async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FollowRelationScreen(
            service: widget.service,
            handle: widget.handle,
          ),
        ),
      );
      await _load();
    },
  );

  Widget _statCard({
    required String label,
    required String value,
    required String sub,
    bool warn = false,
    VoidCallback? onTap,
  }) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: warn ? Colors.orange : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// 3 等分の幅に収める。4 桁までは素の数字のほうが読みやすい
  static String _compact(int v) =>
      v >= 10000 ? '${(v / 10000).toStringAsFixed(1)}万' : '$v';

  // ─── 取得 ───

  Widget _actionSection(FollowTarget t) {
    final resumable = _history.where((s) => s.isResumable).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('今すぐ取得'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _job.isRunning ? null : _startWithConfirm,
          ),
          // 実行アカウントは取得ボタンのすぐ下に置く。鍵アカウント相手だと
          // ここを変えないと取れないので、離れていると
          // 「取得 → 失敗 → 設定を探す」の往復になる
          Row(
            children: [
              const Icon(Icons.account_circle_outlined, size: 18),
              const SizedBox(width: 8),
              const Text('実行アカウント', style: TextStyle(fontSize: 12)),
              const Spacer(),
              if (_usableAccounts.isEmpty)
                const Text(
                  'なし',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                )
              else
                DropdownButton<String>(
                  value: _sessionAccount?.id,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  items: [
                    for (final a in _usableAccounts)
                      DropdownMenuItem(value: a.id, child: Text(a.handle)),
                  ],
                  onChanged: _job.isRunning
                      ? null
                      : (v) => _updateTarget(t.copyWith(sessionAccountId: v)),
                ),
            ],
          ),
          if (widget.service == SnsService.x)
            const Text(
              'X の鍵アカウントは、つながっているアカウントでないと取得できません',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          for (final s in resumable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton.icon(
                icon: const Icon(
                  Icons.play_arrow,
                  size: 18,
                  color: Colors.orange,
                ),
                label: Text(
                  '${s.kind == 'followers' ? 'フォロワー' : 'フォロー'}を'
                  '${s.collectedCount}件目から再開',
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: _job.isRunning
                    ? null
                    : () => _start(
                        s.kind == 'followers'
                            ? FollowListKind.followers
                            : FollowListKind.following,
                        resume: s,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── 定期取得 ───

  Widget _scheduleSection(FollowTarget t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _header('定期取得'),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          '前回の完了から指定日数が過ぎていれば、次の起動時に1回だけ実行します',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ),
      _intervalPicker(
        'フォロワー',
        'followers',
        t.followersIntervalDays,
        (v) => _updateTarget(t.copyWith(followersIntervalDays: v)),
      ),
      _intervalPicker(
        'フォロー',
        'following',
        t.followingIntervalDays,
        (v) => _updateTarget(t.copyWith(followingIntervalDays: v)),
      ),
    ],
  );

  // ─── 履歴 ───

  /// 対象の画面に出す件数。溜まると 40 件近くになるので直近だけ出す
  static const _historyPreview = 3;

  Widget _historySection() {
    if (_history.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('履歴'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'まだ取得していません',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      );
    }
    final shown = _history.take(_historyPreview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _header('履歴 (${_history.length})')),
            if (_history.length > shown.length)
              TextButton(
                onPressed: _openHistory,
                child: const Text('すべて', style: TextStyle(fontSize: 12)),
              ),
            const SizedBox(width: 8),
          ],
        ),
        for (final s in shown)
          followHistoryTile(s, onTap: () => _openSnapshot(s)),
      ],
    );
  }

  // ─── 保存容量と削除 ───

  Widget _storageSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _header('保存容量'),
      _sizeBar(),
      ListTile(
        leading: const Icon(Icons.delete_outline, color: Colors.red),
        title: const Text('この対象と履歴を削除', style: TextStyle(color: Colors.red)),
        onTap: _confirmDelete,
      ),
    ],
  );

  Widget _intervalPicker(
    String label,
    String kind,
    int value,
    ValueChanged<int> onChanged,
  ) => ListTile(
    dense: true,
    title: Text(label),
    subtitle: value <= 0
        ? null
        : Text(
            _nextDueLabel(kind),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
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
              width: 28,
              height: 28,
              child: Icon(Icons.person),
            ),
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
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${p.kind == FollowListKind.followers ? 'フォロワー' : 'フォロー'}'
                    '${p.cancelling ? 'の取得を中断しています…' : 'を取得中'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: p.cancelling ? null : _job.cancel,
                  child: const Text('中断'),
                ),
              ],
            ),
            Text(
              '${p.collected} 件 / ${p.round} ページ',
              style: const TextStyle(fontSize: 20),
            ),
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  // ─── 操作 ───

  Future<void> _openSnapshot(FollowSnapshot s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FollowSnapshotScreen(snapshot: s)),
    );
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
          result?.isCompleted == false ? '中断しました（続きから再開できます）' : '取得が終了しました',
        );
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

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FollowHistoryScreen(service: widget.service, handle: widget.handle),
      ),
    );
    await _load();
  }

  /// 種別の選択と確認を 1 つのシートにまとめる。
  ///
  /// 選択と確認を分けると、始めるのにタップが 3 回要る。最長で数十時間
  /// 走る操作なので確認は要るが、そのぶん「何を・どのアカウントで・
  /// どれくらいかかりそうか」を 1 画面で見せて 1 回で決めさせる。
  /// 所要は前回の実績をそのまま出す（想定件数は走らせるまで分からない）。
  Future<void> _startWithConfirm() async {
    final account = _sessionAccount;
    if (account == null) {
      showAppSnackBar(context, '実行アカウントがありません', type: SnackType.error);
      return;
    }

    var choice = 'both';
    final decided = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
                child: Text(
                  '@${widget.handle} を取得',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '実行アカウント ${account.handle}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const Divider(height: 1),
              _kindChoice(
                choice,
                'followers',
                'フォロワー',
                _latestFollowers,
                (v) => setLocal(() => choice = v),
              ),
              _kindChoice(
                choice,
                'following',
                'フォロー',
                _latestFollowing,
                (v) => setLocal(() => choice = v),
              ),
              _kindChoice(
                choice,
                'both',
                '両方を続けて取得',
                null,
                (v) => setLocal(() => choice = v),
                note: '相互を出すにはこちら',
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('キャンセル'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, choice),
                        child: const Text('取得を開始'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (decided == null || !mounted) return;
    if (decided == 'both') return _startBoth();
    await _start(
      decided == 'followers'
          ? FollowListKind.followers
          : FollowListKind.following,
    );
  }

  Widget _kindChoice(
    String current,
    String value,
    String label,
    FollowSnapshot? last,
    ValueChanged<String> onPick, {
    String? note,
  }) => ListTile(
    dense: true,
    leading: Icon(
      current == value
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked,
      size: 20,
    ),
    title: Text(label),
    subtitle: Text(
      note ??
          (last == null
              ? 'まだ取得していません'
              : '前回 ${last.collectedCount}件'
                    '${durationLabel(last) == null ? '' : ' ・ 所要${durationLabel(last)}'}'),
      style: const TextStyle(fontSize: 11),
    ),
    onTap: () => onPick(value),
  );

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
