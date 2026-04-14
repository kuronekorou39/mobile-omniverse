import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../providers/fetch_status_provider.dart';
import '../providers/settings_provider.dart';
import '../services/timeline_fetch_scheduler.dart';
import '../services/x_query_id_service.dart';
import '../widgets/sns_badge.dart';
import 'login_webview_screen.dart';
import 'notification_webview_screen.dart';
import 'session_refresh_screen.dart';
import 'settings_screen.dart';
import 'user_profile_screen.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountProvider);

    return Scaffold(
      appBar: accounts.isNotEmpty
          ? AppBar(
              leadingWidth: 0,
              leading: const SizedBox.shrink(),
              titleSpacing: 16,
              title: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: const Alignment(0.03, 0.0),
                      child: Image.asset(
                        'assets/logo.png',
                        height: 36,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined, size: 20),
                        tooltip: '設定',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        ),
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            )
          : null,
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
          : Column(
              children: [
                // 全ON/OFF
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () => ref.read(accountProvider.notifier).enableAll(),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('全ON'),
                      ),
                      TextButton(
                        onPressed: () => ref.read(accountProvider.notifier).disableAll(),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: Colors.grey,
                        ),
                        child: const Text('全OFF'),
                      ),
                    ],
                  ),
                ),
                // 並び替え可能なアカウントリスト + 追加ボタン
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: accounts.length + 1,
                    onReorder: (oldIndex, newIndex) {
                      // 追加ボタン行は並び替え対象外
                      if (oldIndex >= accounts.length || newIndex > accounts.length) return;
                      ref.read(accountProvider.notifier).reorder(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      if (index == accounts.length) {
                        return Padding(
                          key: const ValueKey('_add_account'),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          child: OutlinedButton.icon(
                            onPressed: () => _showAddAccountDialog(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('アカウントを追加'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        );
                      }
                      return _AccountTile(
                        key: ValueKey(accounts[index].id),
                        account: accounts[index],
                        index: index,
                      );
                    },
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

    // 同じサービス+ハンドルのアカウントが既に存在するかチェック
    final existing = ref.read(accountProvider);
    final duplicate = existing.any((a) =>
        a.service == result.service &&
        a.handle.toLowerCase() == result.handle.toLowerCase());
    if (duplicate) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.handle} は既に追加されています')),
        );
      }
      return;
    }

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

    // X アカウントで NotificationsTimeline queryId が未取得なら自動取得
    if (service == SnsService.x && context.mounted) {
      final creds = (result.credentials as XCredentials);
      final queryId = XQueryIdService.instance.getQueryId('NotificationsTimeline', creds: creds);
      if (queryId.isEmpty) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => NotificationWebViewScreen(account: account, autoSave: true),
          ),
        );
      }
    }
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({super.key, required this.account, required this.index});

  final Account account;
  final int index;

  static Color _healthColor(AccountHealth health) {
    switch (health) {
      case AccountHealth.good:
        return Colors.green;
      case AccountHealth.warning:
        return Colors.orange;
      case AccountHealth.error:
        return Colors.red;
      case AccountHealth.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fetchStatus = ref.watch(fetchStatusProvider);
    final status = fetchStatus[account.id];
    final health = account.isEnabled
        ? (status?.health ?? AccountHealth.unknown)
        : AccountHealth.unknown;

    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
          ),
          const SizedBox(width: 8),
          Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
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
          Positioned(
            left: -2,
            bottom: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _healthColor(health),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              account.displayName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (account.isProtected) ...[
            const SizedBox(width: 3),
            Icon(Icons.lock, size: 13, color: Colors.grey[500]),
          ],
          const SizedBox(width: 8),
          SnsBadge(service: account.service),
        ],
      ),
      subtitle: Text(account.handle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'ユーザーホーム',
            onPressed: () => _openProfile(context),
          ),
          Switch(
            value: account.isEnabled,
            onChanged: (_) {
              ref.read(accountProvider.notifier).toggleAccount(account.id);
            },
          ),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () => _openDetail(context),
    );
  }

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          username: account.displayName,
          handle: account.handle,
          service: account.service,
          avatarUrl: account.avatarUrl,
          accountId: account.id,
        ),
      ),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'ユーザーホーム',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                    username: account.displayName,
                    handle: account.handle,
                    service: account.service,
                    avatarUrl: account.avatarUrl,
                    accountId: account.id,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'セッション更新',
            onPressed: () => _openSessionRefresh(context, ref, account),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'アカウント削除',
            onPressed: () => _confirmDelete(context, ref, account),
          ),
        ],
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      account.displayName,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (account.isProtected) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.lock, size: 16, color: Colors.grey[500]),
                    ],
                  ],
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
            subtitle: const Text('このアカウントの投稿をフィードに表示する'),
            value: account.isEnabled,
            onChanged: (_) {
              ref.read(accountProvider.notifier).toggleAccount(account.id);
            },
          ),
          // RT/リポスト非表示
          SwitchListTile(
            title: const Text('フォロー先の RT を非表示'),
            subtitle: const Text('このアカウントのフィードから他ユーザーの RT/リポストを除外する'),
            value: ref.watch(settingsProvider).hideRetweetsAccountIds.contains(account.id),
            onChanged: (_) {
              ref.read(settingsProvider.notifier).toggleHideRetweets(account.id);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openSessionRefresh(
      BuildContext context, WidgetRef ref, Account account) async {
    final result = await Navigator.of(context).push<SessionRefreshResult>(
      MaterialPageRoute(
        builder: (_) => SessionRefreshScreen(account: account),
      ),
    );

    if (result == null) return;

    // 更新前の値を記録
    final oldCreds = account.service == SnsService.x ? account.xCredentials : null;
    final oldCt0 = oldCreds?.ct0 ?? '';
    final oldCookieLen = oldCreds?.allCookies.length ?? 0;

    await ref
        .read(accountProvider.notifier)
        .updateCredentials(account.id, result.credentials);

    // スケジューラの期限切れ状態をクリア → 次回フェッチで再試行
    TimelineFetchScheduler.instance.clearExpiredState(account.id);

    // 更新後の値を取得
    String detail = '';
    if (result.credentials is XCredentials) {
      final newCreds = result.credentials as XCredentials;
      final ct0Changed = oldCt0 != newCreds.ct0;
      detail = '\nct0: ${ct0Changed ? "変更あり" : "変更なし"}'
          ' (${newCreds.ct0.length > 8 ? newCreds.ct0.substring(0, 8) : newCreds.ct0}...)'
          '\ncookies: ${newCreds.allCookies.length} chars'
          '${oldCookieLen != newCreds.allCookies.length ? " (前: $oldCookieLen)" : ""}';
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('セッションを更新しました$detail'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
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
