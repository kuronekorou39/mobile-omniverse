import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/dm_models.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_api_service.dart';
import '../services/x_dm_parser.dart';
import '../utils/image_headers.dart';

/// DM のスレッド表示（見る専）。
///
/// 送信欄はなく、既読をつける API も呼ばない。開いても相手からは
/// 未読のままに見える。
class DmThreadScreen extends ConsumerStatefulWidget {
  const DmThreadScreen({
    super.key,
    required this.account,
    required this.conversation,
    this.selfUserId,
  });

  final Account account;
  final DmConversation conversation;

  /// X: 一覧側で解決した自分の user_id
  final String? selfUserId;

  @override
  ConsumerState<DmThreadScreen> createState() => _DmThreadScreenState();
}

class _DmThreadScreenState extends ConsumerState<DmThreadScreen> {
  /// 新しい順（reverse ListView の index 0 が最新 = 画面の一番下）
  final List<DmMessage> _messages = [];
  final Set<String> _messageIds = {};
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _nextCursor;

  Account get _account => widget.account;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_account.service == SnsService.x) {
        final res = await XApiService.instance
            .getDmConversation(_account.xCredentials, widget.conversation.id);
        if (res.data == null) {
          setState(() =>
              _error = 'DM を取得できませんでした（コード ${res.statusCode}）');
        } else {
          final page = XDmParser.parseThread(res.data!,
              selfUserId: widget.selfUserId, selfHandle: _account.handle);
          setState(() {
            _messages.clear();
            _messageIds.clear();
            _append(page.messages);
            _nextCursor = page.nextMaxId;
          });
        }
      } else {
        final res = await BlueskyApiService.instance.getConvoMessagesWithRefresh(
            _account.blueskyCredentials, widget.conversation.id);
        _persistRefreshedCreds(res.updatedCreds);
        if (mounted) {
          setState(() {
            _messages.clear();
            _messageIds.clear();
            _append(res.messages);
            _nextCursor = res.messages.isEmpty ? null : res.cursor;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      if (_account.service == SnsService.x) {
        final res = await XApiService.instance.getDmConversation(
            _account.xCredentials, widget.conversation.id,
            maxId: cursor);
        if (res.data != null) {
          final page = XDmParser.parseThread(res.data!,
              selfUserId: widget.selfUserId, selfHandle: _account.handle);
          setState(() {
            _append(page.messages);
            _nextCursor = page.messages.isEmpty ? null : page.nextMaxId;
          });
        }
      } else {
        final res = await BlueskyApiService.instance.getConvoMessagesWithRefresh(
            _account.blueskyCredentials, widget.conversation.id,
            cursor: cursor);
        _persistRefreshedCreds(res.updatedCreds);
        if (mounted) {
          setState(() {
            _append(res.messages);
            _nextCursor = res.messages.isEmpty ? null : res.cursor;
          });
        }
      }
    } catch (e) {
      debugPrint('[DmThread] loadMore failed: $e');
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  void _append(List<DmMessage> add) {
    for (final m in add) {
      if (_messageIds.add(m.id)) _messages.add(m);
    }
  }

  void _persistRefreshedCreds(BlueskyCredentials? updated) {
    if (updated == null) return;
    ref.read(accountProvider.notifier).updateCredentials(_account.id, updated);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.title.isEmpty ? 'DM' : c.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16)),
            const Text('既読はつきません',
                style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
      body: Column(children: [
        Expanded(child: _body()),
        // 送信欄の代わり。読み取り専用であることを常に示す
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SafeArea(
            top: false,
            child: const Text(
              '読み取り専用（送信・既読なし）',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('再読み込み')),
          ]),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('メッセージがありません'));
    }
    final hasMore = _nextCursor != null;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          // reverse リストの末尾 = 画面の一番上
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : OutlinedButton(
                      onPressed: _loadMore,
                      child: const Text('さらに前を読み込む')),
            ),
          );
        }
        return _bubble(_messages[index]);
      },
    );
  }

  Widget _bubble(DmMessage m) {
    final theme = Theme.of(context);
    final mine = m.isMine;
    final member = widget.conversation.memberFor(m.senderId);
    final senderName = m.senderName ?? member?.label;
    final avatarUrl = m.senderAvatarUrl ?? member?.avatarUrl;

    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mine
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(mine ? 14 : 3),
          bottomRight: Radius.circular(mine ? 3 : 14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.mediaUrl != null) _media(m),
          if (m.mediaUrl == null && m.attachmentLabel != null)
            _attachmentChip(m.attachmentLabel!),
          if (m.text.isNotEmpty)
            Text(m.text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            CircleAvatar(
              radius: 12,
              backgroundImage: avatarUrl == null
                  ? null
                  : CachedNetworkImageProvider(avatarUrl,
                      headers: kImageHeaders),
              child: avatarUrl == null
                  ? const Icon(Icons.person, size: 14)
                  : null,
            ),
            const SizedBox(width: 6),
          ],
          if (mine) _timeLabel(m.sentAt),
          Flexible(
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // グループでは誰の発言か分かるように名前を出す
                if (!mine &&
                    widget.conversation.isGroup &&
                    senderName != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 1),
                    child: Text(senderName,
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey[600])),
                  ),
                bubble,
              ],
            ),
          ),
          if (!mine) _timeLabel(m.sentAt),
        ],
      ),
    );
  }

  Widget _timeLabel(DateTime? at) {
    if (at == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final label = sameDay
        ? '${at.hour}:${at.minute.toString().padLeft(2, '0')}'
        : '${at.month}/${at.day}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(label,
          style: TextStyle(fontSize: 9, color: Colors.grey[500])),
    );
  }

  Widget _media(DmMessage m) {
    // X の DM 画像 (ton.x.com) はログイン Cookie がないと 404 になる
    final headers = _account.service == SnsService.x
        ? {...kImageHeaders, 'Cookie': _account.xCredentials.cookieHeader}
        : kImageHeaders;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: m.mediaUrl!,
          httpHeaders: headers,
          fit: BoxFit.cover,
          placeholder: (_, __) => const SizedBox(
              width: 120,
              height: 80,
              child: Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)))),
          errorWidget: (_, __, ___) =>
              _attachmentChip(m.attachmentLabel ?? '画像'),
        ),
      ),
    );
  }

  Widget _attachmentChip(String label) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('[$label]',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      );
}
