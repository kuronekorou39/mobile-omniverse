import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/activity_log_provider.dart';
import '../providers/settings_provider.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_webview_action_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/image_headers.dart';
import '../widgets/sns_badge.dart';
import 'browser_post_debug_screen.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key, this.quotedPost, this.inReplyToPost});

  final Post? quotedPost;
  final Post? inReplyToPost;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _textController = TextEditingController();
  Account? _selectedAccount;
  bool _isPosting = false;

  List<Account> get _accounts {
    final all = AccountStorageService.instance.accounts.where((a) => a.isEnabled).toList();
    // 引用リポスト/リプライ時は同じプラットフォームのアカウントのみ表示
    final targetPost = widget.quotedPost ?? widget.inReplyToPost;
    if (targetPost != null) {
      return all.where((a) => a.service == targetPost.source).toList();
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
    final postSummary = text.length > 40 ? '${text.substring(0, 40)}…' : text;

    try {
      bool success = false;
      int? statusCode;
      String? responseSnippet;

      if (account.service == SnsService.x) {
        // WebView 経由で投稿 (ブラウザ環境を利用してbot検知を回避)
        String? attachmentUrl;
        String? inReplyToId;
        if (widget.quotedPost != null && widget.quotedPost!.permalink != null) {
          attachmentUrl = widget.quotedPost!.permalink;
        }
        if (widget.inReplyToPost != null) {
          inReplyToId = widget.inReplyToPost!.id.replaceFirst('x_', '');
        }
        final wvResult = await XWebViewActionService.instance
            .createTweet(account.xCredentials, text,
                attachmentUrl: attachmentUrl, inReplyToId: inReplyToId);
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
        String? replyUri;
        String? replyCid;
        if (widget.inReplyToPost != null) {
          replyUri = widget.inReplyToPost!.uri;
          replyCid = widget.inReplyToPost!.cid;
        }
        success = await BlueskyApiService.instance
            .createPost(account.blueskyCredentials, text,
                quoteUri: quoteUri, quoteCid: quoteCid,
                replyUri: replyUri, replyCid: replyCid);
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
        showAppSnackBar(context, '投稿しました', type: SnackType.success);
        Navigator.of(context).pop(true);
      } else {
        showAppSnackBar(context, '投稿に失敗 (${statusCode ?? "?"}). 詳細はアクティビティログで確認', type: SnackType.error);
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
      showAppSnackBar(context, 'エラー: $e', type: SnackType.error);
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isPosting,
      child: Scaffold(
      appBar: AppBar(
        leading: _isPosting ? const SizedBox.shrink() : null,
        title: Text(widget.inReplyToPost != null
            ? 'リプライ'
            : widget.quotedPost != null
                ? '引用リポスト'
                : '投稿'),
        actions: [
          // ブラウザ投稿デバッグ（設定でON + Xアカウント選択時のみ）
          if (ref.watch(settingsProvider).debugPostEnabled &&
              _selectedAccount?.service == SnsService.x)
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
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _isPosting,
            child: Opacity(
              opacity: _isPosting ? 0.5 : 1.0,
              child: Column(
        children: [
          // アカウント選択（チップ横並び、単一選択）
          if (_accounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: _accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final account = _accounts[i];
                    final selected = _selectedAccount?.id == account.id;
                    return _AccountChip(
                      account: account,
                      selected: selected,
                      onTap: () => setState(() => _selectedAccount = account),
                    );
                  },
                ),
              ),
            ),

          // リプライ先プレビュー
          if (widget.inReplyToPost != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SnsBadge(service: widget.inReplyToPost!.source),
                      const SizedBox(width: 6),
                      Text(
                        widget.inReplyToPost!.username,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.inReplyToPost!.handle,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                  if (widget.inReplyToPost!.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.inReplyToPost!.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ],
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

          // 未対応機能プレースホルダーボタン
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final entry in <MapEntry<IconData, String>>[
                  const MapEntry(Icons.image_outlined, '画像'),
                  const MapEntry(Icons.videocam_outlined, '動画'),
                  const MapEntry(Icons.schedule_outlined, '予約投稿'),
                  const MapEntry(Icons.poll_outlined, 'アンケート'),
                  const MapEntry(Icons.reply_outlined, 'リプライ'),
                ])
                  IconButton(
                    icon: Icon(entry.key, color: Colors.grey[400], size: 20),
                    iconSize: 20,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    tooltip: entry.value,
                    onPressed: () {
                      showAppSnackBar(
                        context,
                        '${entry.value}は対応予定なし（公式アプリをご利用ください）',
                        type: SnackType.warning,
                        duration: const Duration(seconds: 2),
                      );
                    },
                  ),
              ],
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
            ),
          ),
          if (_isPosting)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('投稿中...', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
        ],
      ),
    ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final borderColor = selected
        ? primary
        : Theme.of(context).dividerColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 64,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.12) : null,
          border: Border.all(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: selected ? 1.0 : 0.55,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 16,
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
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -4,
                    bottom: -2,
                    child: SnsBadge(service: account.service, size: 7),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              account.handle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? null : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
