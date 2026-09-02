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
import 'dm_thread_screen.dart';

/// DM の会話一覧（見る専）。
///
/// 読み取り専用で、送信欄はない。既読をつける API（X: mark_read /
/// Bluesky: updateRead）はこの機能のどこからも呼ばないので、開いても
/// 相手に既読はつかず、自分の未読も未読のまま残る。
class DmScreen extends ConsumerStatefulWidget {
  const DmScreen({super.key, required this.account});

  final Account account;

  @override
  ConsumerState<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends ConsumerState<DmScreen> {
  final List<DmConversation> _convos = [];
  final Set<String> _convoIds = {};
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// X: 受信箱の続きを読む max_id / Bluesky: cursor
  String? _nextCursor;

  /// X: users マップから解決した自分の user_id（スレッド画面に引き継ぐ）
  String? _selfUserId;

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
        await _loadX();
      } else {
        await _loadBluesky();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadX() async {
    final res = await XApiService.instance.getDmInbox(_account.xCredentials);
    if (res.data == null) {
      setState(() =>
          _error = 'DM を取得できませんでした（コード ${res.statusCode}）');
      return;
    }
    final page =
        XDmParser.parseInbox(res.data!, selfHandle: _account.handle);
    setState(() {
      _convos.clear();
      _convoIds.clear();
      _appendConvos(page.conversations);
      _nextCursor = page.trustedNextMaxId;
      _selfUserId = page.selfUserId;
    });
  }

  Future<void> _loadBluesky() async {
    final res = await BlueskyApiService.instance
        .listConvosWithRefresh(_account.blueskyCredentials);
    _persistRefreshedCreds(res.updatedCreds);
    if (!mounted) return;
    setState(() {
      _convos.clear();
      _convoIds.clear();
      _appendConvos(res.convos);
      _nextCursor = res.convos.isEmpty ? null : res.cursor;
    });
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      if (_account.service == SnsService.x) {
        final res = await XApiService.instance
            .getDmInboxTimeline(_account.xCredentials, maxId: cursor);
        if (res.data != null) {
          final page = XDmParser.parseInbox(res.data!,
              selfUserId: _selfUserId, selfHandle: _account.handle);
          setState(() {
            _appendConvos(page.conversations);
            _nextCursor = page.nextMaxId;
          });
        }
      } else {
        final res = await BlueskyApiService.instance.listConvosWithRefresh(
            _account.blueskyCredentials,
            cursor: cursor);
        _persistRefreshedCreds(res.updatedCreds);
        if (mounted) {
          setState(() {
            _appendConvos(res.convos);
            _nextCursor = res.convos.isEmpty ? null : res.cursor;
          });
        }
      }
    } catch (e) {
      debugPrint('[DmScreen] loadMore failed: $e');
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  void _appendConvos(List<DmConversation> add) {
    for (final c in add) {
      if (_convoIds.add(c.id)) _convos.add(c);
    }
  }

  void _persistRefreshedCreds(BlueskyCredentials? updated) {
    if (updated == null) return;
    ref.read(accountProvider.notifier).updateCredentials(_account.id, updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DM（見る専）'),
            Text(
              _account.displayName,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(children: [
        _readOnlyBanner(),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('再読み込み')),
          ]),
        ),
      ]);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _convos.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return _readOnlyBanner();
        if (index == _convos.length + 1) return _footer();
        return _convoTile(_convos[index - 1]);
      },
    );
  }

  Widget _readOnlyBanner() => Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(children: [
          Icon(Icons.visibility_outlined, size: 18, color: Colors.grey),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '読み取り専用です。開いても相手に既読はつかず、'
              '未読は未読のまま残ります。送信はできません。',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ]),
      );

  Widget _footer() {
    if (_convos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('会話がありません')),
      );
    }
    if (_nextCursor == null) return const SizedBox(height: 24);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: _loadingMore
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : OutlinedButton(
                onPressed: _loadMore, child: const Text('さらに読み込む')),
      ),
    );
  }

  Widget _convoTile(DmConversation c) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: c.avatarUrl == null
            ? null
            : CachedNetworkImageProvider(c.avatarUrl!,
                headers: kImageHeaders),
        child: c.avatarUrl == null
            ? Icon(c.isGroup ? Icons.group : Icons.person)
            : null,
      ),
      title: Row(children: [
        Flexible(
          child: Text(
            c.title.isEmpty ? '(不明な会話)' : c.title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: c.hasUnread ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        if (c.isRequest) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('リクエスト',
                style: TextStyle(fontSize: 9, color: Colors.grey)),
          ),
        ],
        if (c.muted) ...[
          const SizedBox(width: 4),
          const Icon(Icons.volume_off, size: 14, color: Colors.grey),
        ],
      ]),
      subtitle: Text(
        c.lastText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (c.lastAt != null)
            Text(_formatTimeAgo(c.lastAt!),
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          if (c.hasUnread) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                // Bluesky は件数、X は有無だけ分かる
                c.unreadCount != null && c.unreadCount! > 0
                    ? '${c.unreadCount}'
                    : '未読',
                style: TextStyle(
                    fontSize: 9, color: theme.colorScheme.onPrimary),
              ),
            ),
          ],
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DmThreadScreen(
            account: _account,
            conversation: c,
            selfUserId: _selfUserId,
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return '今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分';
    if (diff.inHours < 24) return '${diff.inHours}時間';
    if (diff.inDays < 7) return '${diff.inDays}日';
    return '${ts.month}/${ts.day}';
  }
}
