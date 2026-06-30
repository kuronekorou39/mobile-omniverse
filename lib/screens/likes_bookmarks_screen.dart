import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/account_provider.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_api_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/post_card.dart';
import 'post_detail_screen.dart';

enum _ListKind { likes, bookmarks }

/// 自分の「ふぁぼ（いいね）」と「ブックマーク」を表示する画面。
/// アカウント一覧の各アカウントメニューから開く。タブで2種を切り替える。
class LikesBookmarksScreen extends ConsumerStatefulWidget {
  const LikesBookmarksScreen({
    super.key,
    required this.account,
    this.initialIndex = 0,
  });

  final Account account;

  /// 0 = ふぁぼ, 1 = ブックマーク
  final int initialIndex;

  @override
  ConsumerState<LikesBookmarksScreen> createState() =>
      _LikesBookmarksScreenState();
}

class _LikesBookmarksScreenState extends ConsumerState<LikesBookmarksScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.account.displayName,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'ふぁぼ'),
            Tab(text: 'ブックマーク'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PostListTab(account: widget.account, kind: _ListKind.likes),
          _PostListTab(account: widget.account, kind: _ListKind.bookmarks),
        ],
      ),
    );
  }
}

/// 1タブ分の投稿リスト（ページング・プルリフレッシュ付き）
class _PostListTab extends ConsumerStatefulWidget {
  const _PostListTab({required this.account, required this.kind});

  final Account account;
  final _ListKind kind;

  @override
  ConsumerState<_PostListTab> createState() => _PostListTabState();
}

class _PostListTabState extends ConsumerState<_PostListTab>
    with AutomaticKeepAliveClientMixin {
  final List<Post> _posts = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _cursor;
  String? _error;

  /// X のいいね取得に必要な自分の rest_id（一度だけ解決してキャッシュ）
  String? _xRestId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  /// 最新の認証情報を反映するため provider から取り直す
  Account get _account {
    final accounts = ref.read(accountProvider);
    return accounts.firstWhere(
      (a) => a.id == widget.account.id,
      orElse: () => widget.account,
    );
  }

  Future<({List<Post> posts, String? cursor})> _fetch(String? cursor) async {
    final account = _account;
    final isLikes = widget.kind == _ListKind.likes;

    if (account.service == SnsService.x) {
      final creds = account.xCredentials;
      if (isLikes) {
        _xRestId ??=
            await XApiService.instance.getRestId(creds, account.handle);
        final restId = _xRestId;
        if (restId == null || restId.isEmpty) {
          throw Exception('ユーザーID(rest_id)を取得できませんでした');
        }
        return XApiService.instance
            .getLikes(creds, restId, accountId: account.id, cursor: cursor);
      }
      return XApiService.instance
          .getBookmarks(creds, accountId: account.id, cursor: cursor);
    }

    // Bluesky
    final creds = account.blueskyCredentials;
    if (isLikes) {
      final result = await BlueskyApiService.instance.getActorLikesWithRefresh(
        creds,
        creds.did,
        accountId: account.id,
        cursor: cursor,
      );
      _persistRefreshedCreds(account.id, result.updatedCreds);
      return (posts: result.posts, cursor: result.cursor);
    }
    final result = await BlueskyApiService.instance.getBookmarksWithRefresh(
      creds,
      accountId: account.id,
      cursor: cursor,
    );
    _persistRefreshedCreds(account.id, result.updatedCreds);
    return (posts: result.posts, cursor: result.cursor);
  }

  void _persistRefreshedCreds(String accountId, BlueskyCredentials? updated) {
    if (updated != null) {
      ref.read(accountProvider.notifier).updateCredentials(accountId, updated);
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _fetch(null);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(result.posts);
        _cursor = result.cursor;
        _hasMore = result.cursor != null && result.posts.isNotEmpty;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _cursor == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _fetch(_cursor);
      if (!mounted) return;
      final existing = _posts.map((p) => p.id).toSet();
      final newPosts =
          result.posts.where((p) => !existing.contains(p.id)).toList();
      setState(() {
        _posts.addAll(newPosts);
        _cursor = result.cursor;
        _hasMore = result.cursor != null && newPosts.isNotEmpty;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    final isLikes = widget.kind == _ListKind.likes;
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
            EmptyState(
              icon: isLikes ? Icons.favorite_border : Icons.bookmark_border,
              title: isLikes
                  ? 'いいねした投稿はありません'
                  : 'ブックマークした投稿はありません',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final post = _posts[index];
          return PostCard(
            post: post,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PostDetailScreen(post: post),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              '読み込みに失敗しました',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}
