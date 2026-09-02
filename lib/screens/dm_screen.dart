import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/dm_models.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../services/bluesky_api_service.dart';
import '../services/debug_log_service.dart';
import '../services/x_api_service.dart';
import '../services/x_dm_parser.dart';
import '../utils/image_headers.dart';
import 'dm_thread_screen.dart';
import 'user_profile_screen.dart';

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

  // ─ フィルタ ─
  final _searchController = TextEditingController();
  String _search = '';
  bool _unreadOnly = false;
  bool _requestOnly = false;
  bool _groupOnly = false;

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    // 取得漏れの調査用: 応答に入っていた entry の種類を残す
    DebugLogService.instance.log('DmParse',
        'inbox: convos=${page.conversations.length} '
        'types=${XDmParser.entryTypeHistogram(res.data!)}');
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

  List<DmConversation> get _filtered {
    final q = _search.trim().toLowerCase();
    return _convos.where((c) {
      if (_unreadOnly && !c.hasUnread) return false;
      if (_requestOnly && !c.isRequest) return false;
      if (_groupOnly && !c.isGroup) return false;
      if (q.isEmpty) return true;
      if (c.title.toLowerCase().contains(q)) return true;
      for (final m in c.members) {
        if (m.handle?.toLowerCase().contains(q) == true) return true;
        if (m.displayName?.toLowerCase().contains(q) == true) return true;
        if (m.id.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
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
    final filtered = _filtered;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: filtered.length + 3,
      itemBuilder: (context, index) {
        if (index == 0) return _readOnlyBanner();
        if (index == 1) return _filterBar();
        if (index == filtered.length + 2) return _footer(filtered);
        return _convoTile(filtered[index - 2]);
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

  Widget _filterBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Column(children: [
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '名前・ID で検索',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            _chip('未読', _unreadOnly, (v) => setState(() => _unreadOnly = v)),
            const SizedBox(width: 6),
            _chip('リクエスト', _requestOnly,
                (v) => setState(() => _requestOnly = v)),
            const SizedBox(width: 6),
            _chip('グループ', _groupOnly, (v) => setState(() => _groupOnly = v)),
          ]),
        ]),
      );

  Widget _chip(String label, bool selected, ValueChanged<bool> onChanged) =>
      FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: onChanged,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      );

  Widget _footer(List<DmConversation> filtered) {
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
            child: Text(_convos.isEmpty ? '会話がありません' : '該当なし')),
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

  /// アイコンからプロフィールへ。グループは相手を選んでもらう
  void _openProfile(DmConversation c) {
    if (c.members.isEmpty) return;
    if (c.members.length == 1) {
      _pushProfile(c.members.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in c.members)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundImage: m.avatarUrl == null
                      ? null
                      : CachedNetworkImageProvider(m.avatarUrl!,
                          headers: kImageHeaders),
                  child: m.avatarUrl == null
                      ? const Icon(Icons.person, size: 14)
                      : null,
                ),
                title: Text(m.label, style: const TextStyle(fontSize: 13)),
                subtitle: m.handle == null
                    ? null
                    : Text('@${m.handle}', style: const TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pushProfile(m);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _pushProfile(DmMember m) {
    final handle = m.handle;
    if (handle == null || handle.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UserProfileScreen(
        username: m.displayName ?? handle,
        handle: handle.startsWith('@') ? handle.substring(1) : handle,
        service: _account.service,
        avatarUrl: m.avatarUrl,
        accountId: _account.id,
      ),
    ));
  }

  Widget _convoTile(DmConversation c) {
    final theme = Theme.of(context);
    return ListTile(
      leading: GestureDetector(
        onTap: () => _openProfile(c),
        child: CircleAvatar(
          backgroundImage: c.avatarUrl == null
              ? null
              : CachedNetworkImageProvider(c.avatarUrl!,
                  headers: kImageHeaders),
          child: c.avatarUrl == null
              ? Icon(c.isGroup ? Icons.group : Icons.person)
              : null,
        ),
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
