import 'package:flutter/material.dart';

import '../models/sns_service.dart';
import '../services/follow_capture_job_service.dart';
import '../services/follow_db.dart';
import '../services/follow_history_cleanup.dart';
import '../utils/app_snackbar.dart';
import '../utils/confirm_dialog.dart';
import '../utils/number_format.dart';
import '../widgets/skeleton.dart';
import 'follow_snapshot_screen.dart';

/// 取得履歴の全件。
///
/// 対象の画面には直近だけ出し、溜まった分はこちらで見せる。
/// 多い対象では 40 件近くになるので、1 画面に全部並べると
/// ダッシュボードや設定が押し流されてしまう。
class FollowHistoryScreen extends StatefulWidget {
  const FollowHistoryScreen(
      {super.key, required this.service, required this.handle});

  final SnsService service;
  final String handle;

  @override
  State<FollowHistoryScreen> createState() => _FollowHistoryScreenState();
}

class _FollowHistoryScreenState extends State<FollowHistoryScreen> {
  List<FollowSnapshot> _history = [];
  bool _loading = true;

  /// 「新しい何件を残すか」の選択肢（フォロワー・フォローそれぞれ）
  static const _keepChoices = [3, 5, 10, 20];

  final _cleanup = FollowHistoryCleanup.instance;

  bool get _cleaning => _cleanup.isBusy(widget.service, widget.handle);

  @override
  void initState() {
    super.initState();
    _cleanup.busy.addListener(_onCleanupChanged);
    _load();
  }

  @override
  void dispose() {
    _cleanup.busy.removeListener(_onCleanupChanged);
    super.dispose();
  }

  /// 削除が終わったら、実際に残った分で並べ直す
  void _onCleanupChanged() {
    if (!mounted) return;
    if (_cleaning) {
      setState(() {});
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final rows = await FollowDb.instance.listSnapshots(
        service: widget.service, targetHandle: widget.handle, limit: 500);
    if (!mounted) return;
    setState(() {
      _history = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('@${widget.handle} の履歴'),
        actions: [
          if (_cleaning || _deletableCount(_keepChoices.first) > 0)
            IconButton(
              tooltip: '古い履歴を削除',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _cleaning ? null : _pickKeepCount,
            ),
        ],
        // 削除中であることは上の細い帯だけで示し、画面は止めない
        bottom: _cleaning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _loading
          ? ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [for (var i = 0; i < 8; i++) const _SkeletonTile()],
            )
          : _history.isEmpty
              ? Center(
                  child: Text('まだ取得していません',
                      style: TextStyle(color: scheme.onSurfaceVariant)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _history.length + (_cleaning ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_cleaning && i == 0) return _cleaningNote(scheme);
                      final s = _history[_cleaning ? i - 1 : i];
                      // 消している最中の中身を開くと、途中で消えて壊れて見える
                      return followHistoryTile(
                        s,
                        onTap: _cleaning ? null : () => _open(s),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _cleaningNote(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          '古い履歴を削除しています。終わるまで履歴は開けません。'
          'この画面を離れても削除は続きます。',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      );

  int? get _runningSnapshotId =>
      FollowCaptureJobService.instance.progress.value?.snapshotId;

  /// 新しい [keep] 件ずつ残したときに消える件数（DB 側と同じ条件）。
  /// 残す件数は完了したものだけで数え、途中で止まって再開もできないものは
  /// 新しくても消す。今取得しているものと、再開できるものは消さない
  int _deletableCount(int keep) {
    final completed = <String, int>{};
    var junk = 0;
    for (final s in _history) {
      if (s.id == _runningSnapshotId || s.isResumable) continue;
      if (s.isCompleted) {
        completed[s.kind] = (completed[s.kind] ?? 0) + 1;
      } else {
        junk++;
      }
    }
    return junk +
        completed.values.fold(0, (sum, c) => sum + (c > keep ? c - keep : 0));
  }

  Future<void> _pickKeepCount() async {
    final keep = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 2),
              child: Text('古い履歴を削除',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'フォロワー・フォローそれぞれ、新しい分を残します',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ),
            for (final n in _keepChoices)
              if (_deletableCount(n) case final count)
                ListTile(
                  dense: true,
                  enabled: count > 0,
                  title: Text('新しい $n 件ずつ残す'),
                  trailing: Text(count > 0 ? '$count 件を削除' : '削除なし',
                      style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, n),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (keep == null || !mounted) return;

    final count = _deletableCount(keep);
    final ok = await confirmDialog(
      context,
      title: '古い履歴を削除',
      message: '$count 件の履歴を削除します。元に戻せません。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok || !mounted) return;

    // 終わるまで待たせない。消える分は先に一覧から外し、削除は裏で進める
    final runningId = _runningSnapshotId;
    setState(() => _history = _afterCleanup(keep, runningId));
    // 終わったときにこの画面を離れていても知らせられるよう、
    // アプリ全体の画面から通知を出す
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    try {
      final deleted = await _cleanup.run(widget.service, widget.handle,
          keepPerKind: keep, runningSnapshotId: runningId);
      if (deleted != null && rootContext.mounted) {
        showAppSnackBar(rootContext, '古い履歴を $deleted 件削除しました');
      }
    } catch (e) {
      if (rootContext.mounted) {
        showAppSnackBar(rootContext, '履歴の削除に失敗しました: $e',
            type: SnackType.error);
      }
    }
  }

  /// 削除が終わったあとに残る履歴（DB 側と同じ条件）
  List<FollowSnapshot> _afterCleanup(int keep, int? runningId) {
    final kept = <String, int>{};
    return [
      for (final s in _history)
        if (s.id == runningId || s.isResumable)
          s
        else if (s.isCompleted &&
            (kept[s.kind] = (kept[s.kind] ?? 0) + 1) <= keep)
          s,
    ];
  }

  Future<void> _open(FollowSnapshot s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FollowSnapshotScreen(snapshot: s),
    ));
    await _load();
  }
}

/// 読み込み中の 1 行。[followHistoryTile] と同じ形にしておく
class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) => const ListTile(
        dense: true,
        leading: SkeletonBox(width: 20, height: 20, radius: 10),
        title: Align(
          alignment: Alignment.centerLeft,
          child: SkeletonBox(width: 140, height: 12),
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 90, height: 10),
          ),
        ),
      );
}

/// 履歴の 1 行。対象の画面（直近だけ）と履歴の全件で同じ見た目にする
Widget followHistoryTile(FollowSnapshot s, {VoidCallback? onTap}) => ListTile(
      dense: true,
      // 押せないあいだ（削除中）は薄くして、押せないことを見せる
      enabled: onTap != null,
      leading: Icon(
        s.kind == 'followers'
            ? Icons.group_outlined
            : Icons.person_add_alt_outlined,
        // 完了 / 再開できる / それ以外 を色で分ける
        color: s.isCompleted
            ? Colors.green
            : (s.isResumable ? Colors.orange : Colors.red),
        size: 20,
      ),
      title: Text('${dateLabel(s.startedAt)}  ${formatNumber(s.collectedCount)}件',
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '${s.kind == 'followers' ? 'フォロワー' : 'フォロー'}'
        '${durationLabel(s) == null ? '' : ' ・ 所要${durationLabel(s)}'}'
        '${s.isCompleted ? '' : ' ・ ${statusLabel(s)}'}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
