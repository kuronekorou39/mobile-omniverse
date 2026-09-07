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
import '../widgets/block_scan_section.dart';
import 'follow_history_screen.dart';
import 'follow_relation_screen.dart';
import 'follow_schedule_screen.dart';
import 'follow_snapshot_screen.dart';

/// 走査対象 1 件の詳細。
///
/// この画面は「今の状態」と「今すぐ取得」に絞る。定期取得の設定と履歴の
/// 一覧はそれぞれ別画面に置き、ここには次回予定日と入口だけを出す。
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
      // 走査中の表示は本文の上に重ねる。本文の中に差し込むと、
      // 走査の開始・終了のたびにダッシュボードから下が丸ごとずれる
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: [
                _dashboard(),
                const SizedBox(height: 22),
                _actionSection(t),
                const SizedBox(height: 22),
                // 設定と履歴は面と枠でひとまとめにして、操作から切り離す
                _settingsCard(t),
                BlockScanSection(
                  service: widget.service,
                  handle: widget.handle,
                  account: _sessionAccount,
                  onChanged: _load,
                ),
                _storageSection(),
                // 重ねたカードで最後の項目が隠れないよう、その分だけ空ける
                SizedBox(height: isMine ? _runningCardReserve : 32),
              ],
            ),
          ),
          if (isMine)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _runningCard(running!),
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

  /// 数値を主役にする。取得日などの補足は詰め込まず、警告だけ点で示す
  Widget _statCard({
    required String label,
    required String value,
    required String sub,
    bool warn = false,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  // 取りこぼしは見落とすと後から気づけないので、
                  // 文字を削っても印だけは残す
                  if (warn) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: sub,
                      child: Icon(Icons.error_outline,
                          size: 13, color: scheme.tertiary),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.bold, height: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 3 等分の幅に収める。4 桁までは素の数字のほうが読みやすい
  static String _compact(int v) =>
      v >= 10000 ? '${(v / 10000).toStringAsFixed(1)}万' : '$v';

  // ─── 取得 ───

  Widget _actionSection(FollowTarget t) {
    final resumable = _history.where((s) => s.isResumable).toList();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              textStyle: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: _job.isRunning ? null : _startWithConfirm,
            child: const Text('今すぐ取得'),
          ),
          const SizedBox(height: 12),
          // 実行アカウントは取得ボタンのすぐ下に置く。鍵アカウント相手だと
          // ここを変えないと取れないので、離れていると
          // 「取得 → 失敗 → 設定を探す」の往復になる
          Row(
            children: [
              Text('実行アカウント',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
              const Spacer(),
              if (_usableAccounts.isEmpty)
                Text('なし',
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant))
              else
                DropdownButton<String>(
                  value: _sessionAccount?.id,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                  items: [
                    for (final a in _usableAccounts)
                      DropdownMenuItem(value: a.id, child: Text(a.handle)),
                  ],
                  onChanged: _job.isRunning
                      ? null
                      : (v) => _updateTarget(t.copyWith(sessionAccountId: v)),
                ),
              // 常に出しておくほどの情報ではないので畳む
              if (widget.service == SnsService.x) ...[
                const SizedBox(width: 4),
                Tooltip(
                  triggerMode: TooltipTriggerMode.tap,
                  message:
                      'X の鍵アカウントは、つながっているアカウントでないと取得できません',
                  child: Icon(Icons.info_outline,
                      size: 18, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          // 定期取得の設定は別画面。ここに出すのは次回の予定日だけ
          if (_dueSummary(t) case final due?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.schedule,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      due,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          // 中断した続きは、埋もれると気づかれないので面を持たせる
          for (final s in resumable)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _job.isRunning
                      ? null
                      : () => _start(
                            s.kind == 'followers'
                                ? FollowListKind.followers
                                : FollowListKind.following,
                            resume: s,
                          ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 14),
                    child: Row(
                      children: [
                        Icon(Icons.play_arrow,
                            size: 20, color: scheme.onTertiaryContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${s.kind == 'followers' ? 'フォロワー' : 'フォロー'} '
                            '${s.collectedCount}件目から',
                            style: TextStyle(
                                fontSize: 13,
                                color: scheme.onTertiaryContainer),
                          ),
                        ),
                        Text('再開',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: scheme.onTertiaryContainer)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── 定期取得 ───

  /// 定期取得と履歴。どちらも「開くと別画面」なので 1 枚にまとめる
  Widget _settingsCard(FollowTarget t) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: Column(
          children: [
            _linkRow(
              icon: Icons.autorenew,
              label: '定期取得',
              value: _scheduleSummary(t),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => FollowScheduleScreen(target: t)),
                );
                await _load();
              },
            ),
            Container(height: 1, color: scheme.outlineVariant),
            _linkRow(
              icon: Icons.history,
              label: '履歴',
              value: _history.isEmpty ? 'なし' : '${_history.length}件',
              onTap: _history.isEmpty ? null : _openHistory,
            ),
          ],
        ),
      ),
    );
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            Text(value,
                style:
                    TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right,
                size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _scheduleSummary(FollowTarget t) {
    final parts = <String>[];
    if (t.followersIntervalDays > 0) {
      parts.add('フォロワー ${t.followersIntervalDays}日おき');
    }
    if (t.followingIntervalDays > 0) {
      parts.add('フォロー ${t.followingIntervalDays}日おき');
    }
    return parts.isEmpty ? 'なし' : parts.join(' / ');
  }

  /// 取得ボタンのそばに出す次回予定。設定していなければ出さない
  String? _dueSummary(FollowTarget t) {
    String at(String kind) =>
        nextDueLabel(_nextDue[kind]).replaceFirst('次回: ', '');
    final parts = <String>[];
    if (t.followersIntervalDays > 0) {
      parts.add('フォロワー ${at('followers')}');
    }
    if (t.followingIntervalDays > 0) {
      parts.add('フォロー ${at('following')}');
    }
    return parts.isEmpty ? null : '次回  ${parts.join('  /  ')}';
  }

  // ─── 履歴（一覧は履歴画面にまとめる） ───

  /// 走査中カードを重ねる分の余白。カードの実寸に合わせた概算
  static const _runningCardReserve = 190.0;


  // ─── 保存容量と削除 ───

  Widget _storageSection() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storage, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(child: _sizeBar()),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _confirmDelete,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: scheme.error),
                  const SizedBox(width: 10),
                  Text('この対象と履歴を削除',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: scheme.error)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sizeBar() {
    final limit = _job.sizeLimitBytes;
    final ratio = limit == 0 ? 0.0 : (_sizeBytes / limit).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Expanded(
              child: Text('保存容量',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            Text(
              '${formatBytes(_sizeBytes)} / ${formatBytes(limit)}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: ratio, minHeight: 6),
        ),
      ],
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
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      elevation: 6,
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
