import 'package:flutter/material.dart';

import '../services/follow_capture_job_service.dart';
import '../services/follow_db.dart';
import 'follow_snapshot_screen.dart';

/// 定期取得の設定。
///
/// 対象の画面には次回予定日だけを出し、間隔の変更はこちらに寄せる。
/// 取得ボタンのまわりに設定を並べると、普段使う「今すぐ取得」が
/// 設定に埋もれるため。
class FollowScheduleScreen extends StatefulWidget {
  const FollowScheduleScreen({super.key, required this.target});

  final FollowTarget target;

  @override
  State<FollowScheduleScreen> createState() => _FollowScheduleScreenState();
}

class _FollowScheduleScreenState extends State<FollowScheduleScreen> {
  static const _intervalChoices = [0, 1, 3, 7];

  late FollowTarget _target = widget.target;
  final Map<String, DateTime?> _nextDue = {};

  @override
  void initState() {
    super.initState();
    _loadDue();
  }

  Future<void> _loadDue() async {
    for (final kind in const ['followers', 'following']) {
      _nextDue[kind] = await FollowCaptureJobService.nextDueAt(_target, kind);
    }
    if (mounted) setState(() {});
  }

  Future<void> _update(FollowTarget updated) async {
    await FollowDb.instance.upsertTarget(updated);
    if (!mounted) return;
    setState(() => _target = updated);
    await _loadDue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@${_target.handle} の定期取得')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '前回の完了から指定日数が過ぎていれば、次の起動時に1回だけ実行します',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          _intervalPicker(
            'フォロワー',
            'followers',
            _target.followersIntervalDays,
            (v) => _update(_target.copyWith(followersIntervalDays: v)),
          ),
          _intervalPicker(
            'フォロー',
            'following',
            _target.followingIntervalDays,
            (v) => _update(_target.copyWith(followingIntervalDays: v)),
          ),
        ],
      ),
    );
  }

  Widget _intervalPicker(
    String label,
    String kind,
    int value,
    ValueChanged<int> onChanged,
  ) => ListTile(
    title: Text(label),
    subtitle: value <= 0
        ? null
        : Text(
            nextDueLabel(_nextDue[kind]),
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
}

/// 次回予定日の表示。対象の画面と設定画面で同じ文言を使う
String nextDueLabel(DateTime? due) {
  if (due == null) return '次回: 未定';
  if (!due.isAfter(DateTime.now())) return '次回: 次の起動時';
  return '次回: ${dateLabel(due)}';
}
