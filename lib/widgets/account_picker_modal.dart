import 'package:flutter/material.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import 'sns_badge.dart';

/// いいね/RT 時にどのアカウントで実行するかを選択するモーダル
/// 同じサービスの有効なアカウント一覧を表示する
Future<Account?> showAccountPickerModal(
  BuildContext context, {
  required SnsService service,
  required String actionLabel,
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
                ],
              ),
              subtitle: Text(account.handle),
              onTap: () => Navigator.of(ctx).pop(account),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
