import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_log.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/sns_badge.dart';

class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  String? _accountFilter;
  bool? _successFilter;

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(activityLogProvider);

    // アカウント一覧
    final accounts = <String>{};
    for (final log in logs) {
      accounts.add(log.accountHandle);
    }

    // フィルタ適用
    var filtered = logs;
    if (_accountFilter != null) {
      filtered = filtered.where((l) => l.accountHandle == _accountFilter).toList();
    }
    if (_successFilter != null) {
      filtered = filtered.where((l) => l.success == _successFilter).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('アクションログ'),
        actions: [
          // 成否フィルタ
          PopupMenuButton<bool?>(
            icon: Icon(
              Icons.filter_list,
              color: _successFilter != null ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: '成否フィルタ',
            onSelected: (value) => setState(() => _successFilter = value),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('すべて')),
              const PopupMenuItem(value: true, child: Text('成功のみ')),
              const PopupMenuItem(value: false, child: Text('失敗のみ')),
            ],
          ),
          // アカウントフィルタ
          PopupMenuButton<String?>(
            icon: Icon(
              Icons.person_outline,
              color: _accountFilter != null ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: 'アカウントフィルタ',
            onSelected: (value) => setState(() => _accountFilter = value),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('全アカウント')),
              for (final handle in accounts)
                PopupMenuItem(value: handle, child: Text(handle)),
            ],
          ),
        ],
      ),
      body: filtered.isEmpty
          ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'ログがありません')
          : ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.withAlpha(30)),
              itemBuilder: (context, index) => _LogTile(log: filtered[index]),
            ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});
  final ActivityLog log;

  @override
  Widget build(BuildContext context) {
    final hasError = !log.success;

    return InkWell(
      onTap: log.errorMessage != null || log.responseSnippet != null || log.targetSummary != null
          ? () => _showDetail(context)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 成否 + SNSアイコン
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: log.success ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SnsBadge(service: log.platform, size: 12),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // メイン
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // アクション名 + ステータスコード
                  Row(
                    children: [
                      Text(
                        log.actionLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: hasError ? Colors.red : null,
                        ),
                      ),
                      if (log.statusCode != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(${log.statusCode})',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // アカウント + 対象サマリー
                  Text(
                    [
                      log.accountHandle,
                      if (log.targetSummary != null) log.targetSummary,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  // エラーメッセージ
                  if (log.errorMessage != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      log.errorMessage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
            // 時間
            Text(
              _formatTime(log.timestamp),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${log.actionLabel} — ${log.accountHandle}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                '${log.success ? "成功" : "失敗"} · ${_formatTime(log.timestamp)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const Divider(height: 16),
              if (log.targetId != null)
                _row('Target', log.targetId!),
              if (log.targetSummary != null)
                _row('Post', log.targetSummary!),
              if (log.statusCode != null)
                _row('Status', '${log.statusCode}'),
              if (log.errorMessage != null)
                _row('Error', log.errorMessage!, color: Colors.red),
              if (log.responseSnippet != null) ...[
                const SizedBox(height: 8),
                const Text('Response', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      log.responseSnippet!,
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: TextStyle(fontSize: 11, color: color ?? Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 11, color: color), maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  final s = time.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}
