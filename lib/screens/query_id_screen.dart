import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import '../services/x_bearer_token_service.dart';
import '../services/x_query_id_service.dart';
import 'notification_webview_screen.dart';

/// queryId 管理画面（デバッグ用）
/// 全アカウントの queryId を比較表示し、再取得もできる
class QueryIdScreen extends StatefulWidget {
  const QueryIdScreen({super.key});

  @override
  State<QueryIdScreen> createState() => _QueryIdScreenState();
}

class _QueryIdScreenState extends State<QueryIdScreen> {
  @override
  Widget build(BuildContext context) {
    final svc = XQueryIdService.instance;
    final xAccounts = AccountStorageService.instance.accounts
        .where((a) => a.service == SnsService.x)
        .toList();
    final globalIds = svc.currentIds();
    final bearerToken = XBearerTokenService.instance.token;

    return Scaffold(
      appBar: AppBar(
        title: const Text('queryId 管理'),
      ),
      body: ListView(
        children: [
          // Bearer Token
          _SectionHeader(title: 'Bearer Token'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  bearerToken.isNotEmpty ? Icons.check_circle : Icons.error_outline,
                  size: 16,
                  color: bearerToken.isNotEmpty ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bearerToken.isNotEmpty
                        ? '${bearerToken.substring(0, 30)}…'
                        : '未取得',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: bearerToken.isNotEmpty ? null : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // queryId 比較テーブル
          _SectionHeader(title: 'queryId 比較'),
          if (xAccounts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('X アカウントがありません', style: TextStyle(color: Colors.grey)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 12,
                horizontalMargin: 12,
                headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                dataTextStyle: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                columns: [
                  const DataColumn(label: Text('操作名')),
                  const DataColumn(label: Text('グローバル')),
                  for (final a in xAccounts)
                    DataColumn(label: Text(a.handle, style: const TextStyle(fontSize: 11))),
                ],
                rows: globalIds.keys.map((opName) {
                  final globalVal = globalIds[opName] ?? '';
                  return DataRow(cells: [
                    DataCell(Text(opName, style: const TextStyle(fontWeight: FontWeight.bold))),
                    _idCell(globalVal),
                    for (final a in xAccounts)
                      _idCell(
                        svc.getQueryId(opName, creds: a.xCredentials),
                        compareWith: globalVal,
                      ),
                  ]);
                }).toList(),
              ),
            ),

          const Divider(),

          // 再取得ボタン
          _SectionHeader(title: '再取得'),
          for (final a in xAccounts)
            ListTile(
              leading: CircleAvatar(
                radius: 16,
                backgroundImage: a.avatarUrl != null ? NetworkImage(a.avatarUrl!) : null,
                child: a.avatarUrl == null ? const Icon(Icons.person, size: 16) : null,
              ),
              title: Text(a.handle, style: const TextStyle(fontSize: 14)),
              subtitle: const Text('JSバンドルから再取得', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.refresh, size: 20),
              onTap: () => _refreshForAccount(a),
            ),

          const Divider(),
          _SectionHeader(title: '通知 queryId 取得（WebView）'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'NotificationsTimeline はJSバンドルに含まれないため、WebViewで取得します',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          for (final a in xAccounts)
            ListTile(
              leading: CircleAvatar(
                radius: 16,
                backgroundImage: a.avatarUrl != null ? NetworkImage(a.avatarUrl!) : null,
                child: a.avatarUrl == null ? const Icon(Icons.person, size: 16) : null,
              ),
              title: Text(a.handle, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                svc.getQueryId('NotificationsTimeline', creds: a.xCredentials).isNotEmpty
                    ? '取得済み'
                    : '未取得',
                style: TextStyle(
                  fontSize: 11,
                  color: svc.getQueryId('NotificationsTimeline', creds: a.xCredentials).isNotEmpty
                      ? Colors.green
                      : Colors.red,
                ),
              ),
              trailing: const Icon(Icons.open_in_new, size: 20),
              onTap: () => _openNotificationWebView(a),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  DataCell _idCell(String value, {String? compareWith}) {
    final isEmpty = value.isEmpty;
    final isDifferent = compareWith != null && value.isNotEmpty && value != compareWith;

    return DataCell(
      Text(
        isEmpty ? '—' : value,
        style: TextStyle(
          color: isEmpty
              ? Colors.red
              : isDifferent
                  ? Colors.orange
                  : null,
        ),
      ),
    );
  }

  Future<void> _refreshForAccount(Account account) async {
    final count = await XQueryIdService.instance.forceRefresh(account.xCredentials);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${account.handle}: $count 件更新')),
      );
    }
  }

  Future<void> _openNotificationWebView(Account account) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NotificationWebViewScreen(account: account),
      ),
    );
    if (updated == true && mounted) {
      setState(() {});
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
  }
}
