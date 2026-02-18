import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/sns_badge.dart';
import 'login_webview_screen.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountProvider);

    return Scaffold(
      body: accounts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_add, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'アカウント未登録',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'SNS アカウントを追加して\nタイムラインを取得しましょう',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _showAddAccountDialog(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('アカウント追加'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              children: [
                ...accounts.map(
                  (account) => _AccountTile(account: account),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddAccountDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('アカウント追加'),
                  ),
                ),
              ],
            ),
    );
  }

  void _showAddAccountDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'SNS を選択',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            for (final service in SnsService.values)
              ListTile(
                leading: Icon(
                  service == SnsService.x ? Icons.close : Icons.cloud,
                ),
                title: Text(service.label),
                subtitle: Text(service.domain),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openLogin(context, ref, service);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openLogin(
      BuildContext context, WidgetRef ref, SnsService service) async {
    final result = await Navigator.of(context).push<LoginResult>(
      MaterialPageRoute(
        builder: (_) => LoginWebViewScreen(service: service),
      ),
    );

    if (result == null) return;

    final account = Account(
      id: '${service.name}_${DateTime.now().millisecondsSinceEpoch}',
      service: service,
      displayName: result.displayName,
      handle: result.handle,
      avatarUrl: result.avatarUrl,
      credentials: result.credentials,
      createdAt: DateTime.now(),
    );

    await ref.read(accountProvider.notifier).addAccount(account);

    // アカウント追加時にフェッチが停止中なら自動開始
    final settings = ref.read(settingsProvider);
    if (!settings.isFetchingActive) {
      ref.read(settingsProvider.notifier).startFetching();
    }
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            account.avatarUrl != null ? NetworkImage(account.avatarUrl!) : null,
        child: account.avatarUrl == null
            ? Text(
                account.displayName.isNotEmpty
                    ? account.displayName[0].toUpperCase()
                    : '?',
              )
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              account.displayName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SnsBadge(service: account.service),
        ],
      ),
      subtitle: Text(account.handle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: account.isEnabled,
            onChanged: (_) {
              ref.read(accountProvider.notifier).toggleAccount(account.id);
            },
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _openDetail(context),
          ),
        ],
      ),
      onTap: () => _openDetail(context),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AccountDetailScreen(accountId: account.id),
      ),
    );
  }
}

/// アカウント詳細画面
class _AccountDetailScreen extends ConsumerWidget {
  const _AccountDetailScreen({required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountProvider);
    final account = accounts.where((a) => a.id == accountId).firstOrNull;

    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('アカウント')),
        body: const Center(child: Text('アカウントが見つかりません')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(account.displayName),
      ),
      body: ListView(
        children: [
          // プロフィールヘッダー
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: account.avatarUrl != null
                      ? NetworkImage(account.avatarUrl!)
                      : null,
                  child: account.avatarUrl == null
                      ? Text(
                          account.displayName.isNotEmpty
                              ? account.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 32),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  account.displayName,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SnsBadge(service: account.service),
                    const SizedBox(width: 8),
                    Text(
                      account.handle,
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          // 有効/無効
          SwitchListTile(
            title: const Text('タイムライン取得'),
            subtitle: const Text('このアカウントのタイムラインを Omni-Feed に含める'),
            value: account.isEnabled,
            onChanged: (_) {
              ref.read(accountProvider.notifier).toggleAccount(account.id);
            },
          ),
          const Divider(),
          // 情報
          ListTile(
            title: const Text('サービス'),
            trailing: Text(account.service.label),
          ),
          ListTile(
            title: const Text('追加日時'),
            trailing: Text(
              '${account.createdAt.year}/${account.createdAt.month.toString().padLeft(2, '0')}/${account.createdAt.day.toString().padLeft(2, '0')}',
            ),
          ),
          ListTile(
            title: const Text('アカウント ID'),
            trailing: Text(
              account.id,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
          const Divider(),
          // 削除ボタン
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: () => _confirmDelete(context, ref, account),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('アカウントを削除',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Account account) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('アカウント削除'),
        content:
            Text('${account.displayName} (${account.handle}) を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(accountProvider.notifier).removeAccount(account.id);
              Navigator.of(context).pop(); // 詳細画面を閉じる
            },
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }
}
