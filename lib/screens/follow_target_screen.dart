import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import '../services/block_scan_service.dart';
import '../services/follow_capture_engine.dart';
import '../services/follow_capture_job_service.dart';
import '../services/follow_db.dart';
import '../services/follow_history_cleanup.dart';
import '../utils/app_snackbar.dart';
import '../utils/confirm_dialog.dart';
import '../utils/image_headers.dart';
import '../utils/number_format.dart';
import '../widgets/block_scan_section.dart';
import '../widgets/user_detail_section.dart';
import '../widgets/follow_section_header.dart';
import '../widgets/skeleton.dart';
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
  final _scan = BlockScanService.instance;
  final _cleanup = FollowHistoryCleanup.instance;

  /// 古い履歴を裏で削除しているあいだは、履歴に触る操作を止める
  bool get _cleaning => _cleanup.isBusy(widget.service, widget.handle);

  FollowTarget? _target;
  FollowSnapshot? _latestFollowers;
  FollowSnapshot? _latestFollowing;
  ({int mutual, int onlyFollowers, int onlyFollowing})? _relation;
  List<FollowSnapshot> _history = [];
  int _sizeBytes = 0;
  final Map<String, DateTime?> _nextDue = {};
  bool _loading = true;

  /// 終わっていないつながり調査が残っているか
  bool _hasUnfinishedScan = false;

  @override
  void initState() {
    super.initState();
    _job.progress.addListener(_onProgress);
    _scan.progress.addListener(_onScanProgress);
    _cleanup.busy.addListener(_onCleanupChanged);
    _load();
  }

  @override
  void dispose() {
    _job.progress.removeListener(_onProgress);
    _scan.progress.removeListener(_onScanProgress);
    _cleanup.busy.removeListener(_onCleanupChanged);
    super.dispose();
  }

  /// 削除が終わったら件数や容量を読み直す
  void _onCleanupChanged() {
    if (!mounted) return;
    if (_cleaning) {
      setState(() {});
    } else {
      _load();
    }
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  void _onScanProgress() {
    if (!mounted) return;
    // 調査が終わったら、未完了が残っているかを読み直す
    if (_scan.progress.value == null) {
      _load();
    } else {
      setState(() {});
    }
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

    final blockRuns = await db.listBlockRuns(
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
      _hasUnfinishedScan = blockRuns.any((r) => !r.isCompleted);
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

  /// 未完了のつながり調査があるあいだは実行アカウントを替えさせない。
  ///
  /// 調査の結果は「実行アカウントから見た関係」なので、途中で替えると
  /// 別のアカウント視点の結果が 1 つの調査に混ざる。
  ///
  /// 進行中の調査はサービスを持たない (X でしか走らない) ので、
  /// ハンドルの一致だけで見ると他サービスの同名の対象まで止めてしまう
  bool get _scanLocksAccount =>
      _hasUnfinishedScan ||
      (widget.service == SnsService.x &&
          _scan.progress.value?.targetHandle == widget.handle);

  @override
  Widget build(BuildContext context) {
    final t = _target;
    if (_loading) return _loadingScaffold();
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: Text('@${widget.handle}')),
        body: Center(
          // 読み込み表示のまま止まらないよう、理由を出して抜けられるようにする
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'この対象はまだ登録されていません。\n'
              'フォロー / フォロワー取得の画面から追加してください。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final running = _job.progress.value;
    final isMine =
        running?.targetHandle == widget.handle &&
        running?.service == widget.service;

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        // 対象はアイコンと名前で示す。実行アカウントは文字だけにして、
        // 「調べられる側」と「調べる側」を取り違えないようにする
        title: Row(
          children: [
            _avatar(t),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (t.displayName.isNotEmpty)
                    Text(
                      t.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  Text(
                    '@${t.handle}',
                    overflow: TextOverflow.ellipsis,
                    style: t.displayName.isEmpty
                        ? const TextStyle(fontSize: 18)
                        : TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              children: [
                // 取得にも調査にも効くので、どちらのまとまりにも入れず先頭に置く
                _accountSelector(t),
                const SizedBox(height: FollowSectionHeader.sectionGap),
                const FollowSectionHeader('フォロー / フォロワー'),
                _dashboard(),
                const SizedBox(height: 12),
                _captureActions(),
                const SizedBox(height: 12),
                _links(t),
                const SizedBox(height: FollowSectionHeader.sectionGap),
                BlockScanSection(
                  service: widget.service,
                  handle: widget.handle,
                  account: _sessionAccount,
                  onChanged: _load,
                ),
                UserDetailSection(
                  service: widget.service,
                  handle: widget.handle,
                  account: _sessionAccount,
                ),
                const FollowSectionHeader('データ'),
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

  /// 読み込み中も読み込み後と同じ並びで出し、値の部分だけを棒にする。
  /// 中身が入ったときに画面の形が変わらないので、ちらつかない
  Widget _loadingScaffold() => Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const SkeletonBox(
                  width: _avatarSize, height: _avatarSize, radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text('@${widget.handle}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
        body: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          children: [
            const FollowSectionHeader('実行アカウント'),
            Container(
              height: 48,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: const SkeletonBox(width: 120, height: 14),
            ),
            const SizedBox(height: FollowSectionHeader.sectionGap),
            const FollowSectionHeader('フォロー / フォロワー'),
            _dashboard(),
            const SizedBox(height: 12),
            _captureActions(),
            const SizedBox(height: 12),
            _links(null),
          ],
        ),
      );

  // ─── 実行アカウント ───

  Widget _accountSelector(FollowTarget t) {
    final scheme = Theme.of(context).colorScheme;
    final accounts = _usableAccounts;
    final locked = _scanLocksAccount || _job.isRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FollowSectionHeader(
          '実行アカウント',
          // 常に出しておくほどの情報ではないので畳む
          info: widget.service == SnsService.x
              ? 'フォロー/フォロワーの取得と、つながり調査の両方に使います。\n'
                  'X の鍵アカウントは、つながっているアカウントでないと取得できません'
              : null,
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: accounts.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('なし',
                      style: TextStyle(
                          fontSize: 15, color: scheme.onSurfaceVariant)),
                )
              : DropdownButton<String>(
                  value: _sessionAccount?.id,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  icon: Icon(
                      locked ? Icons.lock_outline : Icons.expand_more,
                      size: 20),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(value: a.id, child: Text(a.handle)),
                  ],
                  onChanged: locked
                      ? null
                      : (v) => _updateTarget(t.copyWith(sessionAccountId: v)),
                ),
        ),
        // 取得中は一時的なので黙って止める。調査のほうは数日残りうるので、
        // なぜ替えられないのかを出しておく
        if (_scanLocksAccount)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              '未完了のつながり調査があるあいだは切り替えられません',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  // ─── ダッシュボード ───

  /// フォロワー / フォロー / 相互 を横に並べる。
  ///
  /// 相互だけ取得日時を出さないのは、2 本のスナップショットの突き合わせで
  /// 出しているため「いつ取ったか」が 1 つに定まらないから。実際
  /// フォロワーとフォローの取得日は数日ずれることがある。
  // ListView の中は高さが無制限なので、stretch だけでは
  // カードが無限の高さになる。IntrinsicHeight で 3 枚のうち
  // 一番高いものに合わせて確定させる
  Widget _dashboard() => IntrinsicHeight(
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
  );

  Widget _snapshotCard(String label, FollowSnapshot? s) {
    final warn = s != null && looksIncomplete(s);
    return _statCard(
      label: label,
      value: _loading
          ? null
          : (s == null ? '—' : formatNumber(s.collectedCount)),
      sub: s == null ? '未取得' : (warn ? '取りこぼしの可能性' : dateLabel(s.startedAt)),
      warn: warn,
      onTap: s == null ? null : () => _openSnapshot(s),
    );
  }

  Widget _mutualCard() => _statCard(
    label: '相互',
    value: _loading
        ? null
        : (_relation == null ? '—' : formatNumber(_relation!.mutual)),
    // 未取得でも押させる。遷移先が「何が足りないか」を出す
    sub: _relation == null ? '両方が必要' : '内訳を見る',
    onTap: _loading ? null : () async {
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

  /// 数値を主役にする。取得日などの補足は詰め込まず、警告だけ点で示す。
  /// [value] が null なら読み込み中
  Widget _statCard({
    required String label,
    required String? value,
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
              if (value == null)
                // 数字 1 行（26px）と同じ高さにして、入れ替わりで揺れないようにする
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 3),
                  child: SkeletonBox(width: 56, height: 20),
                )
              else
                // 6 桁を超えると 3 等分の幅に入らないので、そのときだけ縮める
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          height: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 取得 ───

  Widget _captureActions() {
    final resumable = _history.where((s) => s.isResumable).toList();
    final scheme = Theme.of(context).colorScheme;
    return Column(
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
            onPressed: _job.isRunning || _loading || _cleaning
                ? null
                : _startWithConfirm,
            child: const Text('今すぐ取得'),
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
                            '${formatNumber(s.collectedCount)}件目から',
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
    );
  }

  // ─── 定期取得 ───

  /// 定期取得と履歴。面は付けず行だけ並べる。上の数字のカードと同じ面に
  /// すると、似た見た目のものが続いて区別がつかない。
  /// 間隔そのものは設定画面で見られるので、ここには次回だけ出す。
  /// [t] が null なら読み込み中
  Widget _links(FollowTarget? t) => Column(
        children: [
          _linkRow(
            icon: Icons.autorenew,
            label: '定期取得',
            value: t == null ? null : _scheduleValue(t),
            onTap: t == null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => FollowScheduleScreen(target: t)),
                    );
                    await _load();
                  },
          ),
          _linkRow(
            icon: Icons.history,
            label: '履歴',
            value: t == null
                ? null
                : _cleaning
                    ? '削除中…'
                    : (_history.isEmpty ? 'なし' : '${_history.length}件'),
            // 削除中も開ける。開いた先で進み具合が分かり、中身は開けない
            onTap: t == null || _history.isEmpty ? null : _openHistory,
          ),
        ],
      );

  /// 定期取得の状態。間隔は出さず、次に動く日だけ示す
  String _scheduleValue(FollowTarget t) {
    final dues = <DateTime>[];
    var scheduled = false;
    for (final kind in const ['followers', 'following']) {
      if (t.intervalFor(kind) <= 0) continue;
      scheduled = true;
      final due = _nextDue[kind];
      if (due != null) dues.add(due);
    }
    if (!scheduled) return 'なし';
    if (dues.isEmpty) return '未定';
    dues.sort();
    final next = dues.first;
    return next.isAfter(DateTime.now()) ? dateLabel(next) : '次の起動時';
  }

  Widget _linkRow({
    required IconData icon,
    required String label,
    required String? value,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        // 面が無いので、左端を見出しや下の「保存容量」とそろえる
        padding: const EdgeInsets.fromLTRB(4, 12, 0, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            if (value == null)
              const SkeletonBox(width: 48, height: 12)
            else
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // ─── 履歴（一覧は履歴画面にまとめる） ───

  /// 走査中カードを重ねる分の余白。カードの実寸に合わせた概算
  static const _runningCardReserve = 190.0;


  // ─── 保存容量と削除 ───

  Widget _storageSection() {
    final scheme = Theme.of(context).colorScheme;
    final deleteColor = _cleaning
        ? scheme.onSurface.withValues(alpha: 0.38)
        : scheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
            // 履歴を消している最中に対象ごと消すと、二重に消しにいく
            onTap: _cleaning ? null : _confirmDelete,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: deleteColor),
                  const SizedBox(width: 10),
                  Text('この対象と履歴を削除',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: deleteColor)),
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

  static const _avatarSize = 32.0;

  Widget _avatar(FollowTarget t) {
    const fallback = SizedBox(
        width: _avatarSize, height: _avatarSize, child: Icon(Icons.person));
    return ClipOval(
      child: t.avatarUrl.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: t.avatarUrl,
              httpHeaders: kImageHeaders,
              width: _avatarSize,
              height: _avatarSize,
              fit: BoxFit.cover,
              memCacheWidth: 96,
              errorWidget: (_, __, ___) => fallback,
            ),
    );
  }

  Widget _runningCard(FollowJobProgress p) {
    final rate = p.rateLimit;
    final waitLeft = p.waitingUntil?.difference(DateTime.now());
    final scheme = Theme.of(context).colorScheme;
    // 一覧の上に重なるので影で浮かせるが、形はつながり調査や詳しい情報の
    // 「取得中」の面と同じにして、別物に見えないようにする
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 3,
        shadowColor: scheme.shadow,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
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
                '${formatNumber(p.collected)} 件 / ${formatNumber(p.round)} ページ',
                style: const TextStyle(fontSize: 20),
              ),
              Text(
                [
                  if (rate?.remaining != null)
                    'レート残 ${rate!.remaining}/${rate.limit ?? '?'}',
                  '経過 ${elapsedLabel(DateTime.now().difference(p.startedAt))}',
                ].join(' ・ '),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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
                        style: TextStyle(fontSize: 11, color: scheme.tertiary),
                      ),
              ),
            ],
          ),
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
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
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
              : '前回 ${formatNumber(last.collectedCount)}件'
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
