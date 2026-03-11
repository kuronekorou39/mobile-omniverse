import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_api_service.dart';
import '../services/x_webview_action_service.dart';
import '../utils/image_headers.dart';
import '../widgets/sns_badge.dart';
import 'browser_post_debug_screen.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key, this.quotedPost});

  final Post? quotedPost;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _textController = TextEditingController();
  Account? _selectedAccount;
  bool _isPosting = false;

  List<Account> get _accounts {
    final all = AccountStorageService.instance.accounts.where((a) => a.isEnabled).toList();
    // 引用リポスト時は同じプラットフォームのアカウントのみ表示
    final quoted = widget.quotedPost;
    if (quoted != null) {
      return all.where((a) => a.service == quoted.source).toList();
    }
    return all;
  }

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
        // WebView 経由で投稿 (ブラウザ環境を利用してbot検知を回避)
        String? attachmentUrl;
        if (widget.quotedPost != null && widget.quotedPost!.permalink != null) {
          attachmentUrl = widget.quotedPost!.permalink;
        }
        final wvResult = await XWebViewActionService.instance
            .createTweet(account.xCredentials, text, attachmentUrl: attachmentUrl);
        success = wvResult.success;
        statusCode = wvResult.statusCode;
        responseSnippet = '[WebView] ${wvResult.body.length > 500 ? '${wvResult.body.substring(0, 500)}...' : wvResult.body}';
      } else {
        String? quoteUri;
        String? quoteCid;
        if (widget.quotedPost != null) {
          quoteUri = widget.quotedPost!.uri;
          quoteCid = widget.quotedPost!.cid;
        }
        success = await BlueskyApiService.instance
            .createPost(account.blueskyCredentials, text,
                quoteUri: quoteUri, quoteCid: quoteCid);
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
          SnackBar(
            content: Text('投稿に失敗 (${statusCode ?? "?"}). 詳細はアクティビティログで確認'),
          ),
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
        title: Text(widget.quotedPost != null ? '引用リポスト' : '投稿'),
        actions: [
          // ブラウザ投稿デバッグ（Xアカウント選択時のみ）
          if (_selectedAccount?.service == SnsService.x)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined, size: 20),
              tooltip: 'ブラウザで投稿（デバッグ）',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BrowserPostDebugScreen(
                      account: _selectedAccount!,
                    ),
                  ),
                );
              },
            ),
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
                isExpanded: true,
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
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundImage: account.avatarUrl != null
                              ? CachedNetworkImageProvider(
                                  account.avatarUrl!,
                                  headers: kImageHeaders,
                                )
                              : null,
                          child: account.avatarUrl == null
                              ? Text(
                                  account.displayName.isNotEmpty
                                      ? account.displayName[0]
                                      : '?',
                                  style: const TextStyle(fontSize: 14),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        SnsBadge(service: account.service),
                        const SizedBox(width: 8),
                        Expanded(
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
                  CircleAvatar(
                    radius: 14,
                    backgroundImage: _selectedAccount!.avatarUrl != null
                        ? CachedNetworkImageProvider(
                            _selectedAccount!.avatarUrl!,
                            headers: kImageHeaders,
                          )
                        : null,
                    child: _selectedAccount!.avatarUrl == null
                        ? Text(
                            _selectedAccount!.displayName.isNotEmpty
                                ? _selectedAccount!.displayName[0]
                                : '?',
                            style: const TextStyle(fontSize: 14),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
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

          // 引用元プレビュー
          if (widget.quotedPost != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundImage: widget.quotedPost!.avatarUrl != null
                              ? CachedNetworkImageProvider(
                                  widget.quotedPost!.avatarUrl!,
                                  headers: kImageHeaders,
                                )
                              : null,
                          child: widget.quotedPost!.avatarUrl == null
                              ? Text(
                                  widget.quotedPost!.username.isNotEmpty
                                      ? widget.quotedPost!.username[0]
                                      : '?',
                                  style: const TextStyle(fontSize: 10),
                                )
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.quotedPost!.username,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            widget.quotedPost!.handle,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (widget.quotedPost!.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.quotedPost!.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ],
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
