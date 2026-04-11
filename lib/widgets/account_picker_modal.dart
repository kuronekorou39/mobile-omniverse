import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import 'sns_badge.dart';

Widget? _buildEngagementIndicator(
  BuildContext context, {
  required String actionLabel,
  required bool isFetcher,
  bool? isEngaged,
}) {
  if (isEngaged == null) return null;

  // リプライにはステータス表示不要
  final isLikeAction = actionLabel == 'いいね';
  final isRepostAction = actionLabel == 'リポスト';
  if (!isLikeAction && !isRepostAction) return null;

  if (!isFetcher) {
    return Text('?', style: TextStyle(fontSize: 14, color: Colors.grey[500]));
  }

  if (isLikeAction) {
    return Icon(
      isEngaged ? Icons.favorite : Icons.favorite_outline,
      size: 18,
      color: isEngaged ? Colors.red : Colors.grey[400],
    );
  }
  return Icon(
    isEngaged ? Icons.repeat_on : Icons.repeat,
    size: 18,
    color: isEngaged ? Colors.green : Colors.grey[400],
  );
}

/// いいね/RT/リプライ時にどのアカウントで実行するかを選択するモーダル
/// 同じサービスの有効なアカウント一覧を表示する
/// [fetchedByAccountId] は投稿を取得したアカウントID（マーク表示用）
/// [isEngagedByFetcher] は取得元アカウントのエンゲージメント状態（いいね済み/RT済み等）
Future<Account?> showAccountPickerModal(
  BuildContext context, {
  required SnsService service,
  required String actionLabel,
  String? fetchedByAccountId,
  bool? isEngagedByFetcher,
}) async {
  final accounts = AccountStorageService.instance.accounts
      .where((a) => a.service == service && a.isEnabled)
      .toList();

  if (accounts.isEmpty) return null;
  if (accounts.length == 1) return accounts.first;

  return showModalBottomSheet<Account>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '$actionLabel するアカウントを選択',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          for (final account in accounts)
            ListTile(
              leading: CircleAvatar(
                backgroundImage: account.avatarUrl != null
                    ? NetworkImage(account.avatarUrl!)
                    : null,
                child: account.avatarUrl == null
                    ? Text(account.displayName.isNotEmpty
                        ? account.displayName[0].toUpperCase()
                        : '?')
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
                  if (account.id == fetchedByAccountId) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_back, size: 14,
                        color: Theme.of(ctx).colorScheme.primary),
                    Text(' 取得元',
                        style: TextStyle(fontSize: 11,
                            color: Theme.of(ctx).colorScheme.primary)),
                  ],
                ],
              ),
              subtitle: Text(account.handle),
              trailing: _buildEngagementIndicator(
                ctx,
                actionLabel: actionLabel,
                isFetcher: account.id == fetchedByAccountId,
                isEngaged: isEngagedByFetcher,
              ),
              onTap: () => Navigator.of(ctx).pop(account),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
