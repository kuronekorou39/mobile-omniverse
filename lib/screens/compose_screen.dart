import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/activity_log.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_api_service.dart';
import '../widgets/sns_badge.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _textController = TextEditingController();
  Account? _selectedAccount;
  bool _isPosting = false;

  List<Account> get _accounts =>
      AccountStorageService.instance.accounts.where((a) => a.isEnabled).toList();

  @override
  void initState() {
    super.initState();
    if (_accounts.isNotEmpty) {
      _selectedAccount = _accounts.first;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  int get _maxLength =>
      _selectedAccount?.service == SnsService.bluesky ? 300 : 280;

  int get _remaining => _maxLength - _textController.text.length;

  Future<void> _post() async {
    if (_selectedAccount == null || _textController.text.trim().isEmpty) return;

    setState(() => _isPosting = true);

    final text = _textController.text.trim();
    final account = _selectedAccount!;
    final postSummary = text.length > 40 ? '${text.substring(0, 40)}...' : text;

    try {
      bool success = false;
      int? statusCode;
      String? responseSnippet;

      if (account.service == SnsService.x) {
        final result =
            await XApiService.instance.createTweet(account.xCredentials, text);
        success = result.success;
        statusCode = result.statusCode;
        responseSnippet = result.bodySnippet;
      } else {
        success = await BlueskyApiService.instance
            .createPost(account.blueskyCredentials, text);
      }

      ref.read(activityLogProvider.notifier).logAction(
        action: ActivityAction.post,
        platform: account.service,
        accountHandle: account.handle,
        accountId: account.id,
        targetSummary: postSummary,
        success: success,
        statusCode: statusCode,
        responseSnippet: responseSnippet,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('投稿しました')),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('投稿に失敗しました')),
        );
        setState(() => _isPosting = false);
      }
    } catch (e) {
      ref.read(activityLogProvider.notifier).logAction(
        action: ActivityAction.post,
        platform: account.service,
        accountHandle: account.handle,
        accountId: account.id,
        targetSummary: postSummary,
        success: false,
        errorMessage: '$e',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e')),
      );
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('投稿'),
        actions: [
          FilledButton(
            onPressed:
                _isPosting || _textController.text.trim().isEmpty || _remaining < 0
                    ? null
                    : _post,
            child: _isPosting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('投稿'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // アカウント選択
          if (_accounts.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DropdownButtonFormField<Account>(
                initialValue: _selectedAccount,
                decoration: const InputDecoration(
                  labelText: '投稿アカウント',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _accounts.map((account) {
                  return DropdownMenuItem(
                    value: account,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SnsBadge(service: account.service),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${account.displayName} (${account.handle})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (account) {
                  setState(() => _selectedAccount = account);
                },
              ),
            )
          else if (_selectedAccount != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  SnsBadge(service: _selectedAccount!.service),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedAccount!.displayName} (${_selectedAccount!.handle})',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

          // テキスト入力
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'いまどうしてる？',
                  border: InputBorder.none,
                ),
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),

          // 文字数カウンター
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '$_remaining',
                  style: TextStyle(
                    color: _remaining < 0
                        ? Colors.red
                        : _remaining < 20
                            ? Colors.orange
                            : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
