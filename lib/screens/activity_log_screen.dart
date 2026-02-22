import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_log.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';

class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _selectedAccount; // null = 全アカウント

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(activityLogProvider);

    // アカウント一覧を抽出
    final accountSet = <String>{};
    for (final log in logs) {
      accountSet.add(log.accountHandle);
    }
    final accounts = accountSet.toList()..sort();

    // フィルタ適用
    final filtered = _selectedAccount == null
        ? logs
        : logs.where((l) => l.accountHandle == _selectedAccount).toList();

    final commitLogs =
        filtered.where((l) => l.action != ActivityAction.timelineFetch).toList();
    final fetchLogs =
        filtered.where((l) => l.action == ActivityAction.timelineFetch).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'ログクリア',
            onPressed: () {
              ref.read(activityLogProvider.notifier).clear();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(84),
          child: Column(
            children: [
              // アカウントフィルタ
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _FilterChip(
                      label: '全アカウント',
                      selected: _selectedAccount == null,
                      onTap: () => setState(() => _selectedAccount = null),
                    ),
                    ...accounts.map((handle) => _FilterChip(
                          label: handle,
                          selected: _selectedAccount == handle,
                          onTap: () =>
                              setState(() => _selectedAccount = handle),
                        )),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: '操作 (${commitLogs.length})'),
                  Tab(text: 'TL取得 (${fetchLogs.length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LogList(logs: commitLogs),
          _FetchLogList(logs: fetchLogs),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _LogList extends StatelessWidget {
  const _LogList({required this.logs});
  final List<ActivityLog> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
        child: Text('ログがありません', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) => _LogTile(log: logs[index]),
    );
  }
}

class _FetchLogList extends StatelessWidget {
  const _FetchLogList({required this.logs});
  final List<ActivityLog> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
        child: Text('ログがありません', style: TextStyle(color: Colors.grey)),
      );
    }

    // アカウント別に最新のログをグループ化
    final latestByAccount = <String, ActivityLog>{};
    for (final log in logs) {
      final key = '${log.platform.name}_${log.accountHandle}';
      if (!latestByAccount.containsKey(key)) {
        latestByAccount[key] = log;
      }
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最終取得',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              ...latestByAccount.entries.map((entry) {
                final log = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      _platformIcon(log.platform, 14),
                      const SizedBox(width: 6),
                      Text(log.accountHandle,
                          style: const TextStyle(fontSize: 13)),
                      const Spacer(),
                      _successBadge(log.success),
                      const SizedBox(width: 6),
                      Text(
                        _formatTime(log.timestamp),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) => _LogTile(log: logs[index]),
          ),
        ),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});
  final ActivityLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCommit = log.action != ActivityAction.timelineFetch;

    return ExpansionTile(
      leading: _platformIcon(log.platform, 20),
      title: Row(
        children: [
          _successBadge(log.success),
          const SizedBox(width: 6),
          Text(
            log.actionLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isCommit ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (log.statusCode != null) ...[
            const SizedBox(width: 4),
            Text(
              '(${log.statusCode})',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${log.accountHandle}  ${_formatTime(log.timestamp)}',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (log.targetId != null) _detailRow('Target', log.targetId!),
              if (log.targetSummary != null)
                _detailRow('Post', log.targetSummary!),
              if (log.errorMessage != null)
                _detailRow('Error', log.errorMessage!,
                    color: theme.colorScheme.error),
              if (log.responseSnippet != null)
                _detailRow('Response', log.responseSnippet!),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color ?? Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: color),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _platformIcon(SnsService platform, double size) {
  switch (platform) {
    case SnsService.x:
      return Icon(Icons.close, size: size, color: Colors.grey[700]);
    case SnsService.bluesky:
      return Icon(Icons.cloud, size: size, color: Colors.blue);
  }
}

Widget _successBadge(bool success) {
  return Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: success ? Colors.green : Colors.red,
    ),
  );
}

String _formatTime(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  final s = time.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}
