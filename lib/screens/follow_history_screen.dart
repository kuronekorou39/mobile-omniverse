import 'package:flutter/material.dart';

import '../models/sns_service.dart';
import '../services/follow_capture_job_service.dart';
import '../services/follow_db.dart';
import '../utils/app_snackbar.dart';
import '../utils/confirm_dialog.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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
          if (_deletableCount(_keepChoices.first) > 0)
            IconButton(
              tooltip: '古い履歴を削除',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _pickKeepCount,
            ),
        ],
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
                    itemCount: _history.length,
                    itemBuilder: (_, i) => followHistoryTile(
                      _history[i],
                      onTap: () => _open(_history[i]),
                    ),
                  ),
                ),
    );
  }

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

    // 件数が多いと数十秒かかる。黙って待たせると押せていないように見え、
    // 途中で画面を出入りすると読み込みが削除の後ろで止まって見える。
    // 終わるまでここで待ってもらう
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 16),
              Expanded(child: Text('削除しています…')),
            ],
          ),
        ),
      ),
    );
    String? error;
    var deleted = 0;
    try {
      deleted = await FollowDb.instance.deleteOldSnapshots(
          widget.service, widget.handle,
          keepPerKind: keep, runningSnapshotId: _runningSnapshotId);
    } catch (e) {
      error = '$e';
    }
    navigator.pop();
    await _load();
    if (!mounted) return;
    if (error != null) {
      showAppSnackBar(context, '削除に失敗しました: $error', type: SnackType.error);
    } else {
      showAppSnackBar(context, '$deleted 件を削除しました');
    }
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
      title: Text('${dateLabel(s.startedAt)}  ${s.collectedCount}件',
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
