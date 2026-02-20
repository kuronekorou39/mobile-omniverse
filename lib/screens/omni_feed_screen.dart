import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/account_provider.dart';
import '../services/account_storage_service.dart';
import '../services/x_api_service.dart';
import '../services/bluesky_api_service.dart';
import '../models/account.dart';
import '../widgets/post_card.dart';
import 'accounts_screen.dart';
import 'settings_screen.dart';
import 'post_detail_screen.dart';

class OmniFeedScreen extends ConsumerStatefulWidget {
  const OmniFeedScreen({super.key});

  @override
  ConsumerState<OmniFeedScreen> createState() => _OmniFeedScreenState();
}

class _OmniFeedScreenState extends ConsumerState<OmniFeedScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final feed = ref.read(feedProvider);
      if (!feed.isLoadingMore) {
        ref.read(feedProvider.notifier).loadMore();
      }
    }
  }

  Future<void> _handleLike(Post post) async {
    final account = _getAccountForPost(post);
    if (account == null) return;

    // Optimistic update
    ref.read(feedProvider.notifier).updatePostEngagement(
          post.id,
          isLiked: !post.isLiked,
          likeCount: post.isLiked ? post.likeCount - 1 : post.likeCount + 1,
        );

    try {
      if (post.source == SnsService.x) {
        final creds = account.xCredentials;
        final tweetId = post.id.replaceFirst('x_', '');
        if (post.isLiked) {
          await XApiService.instance.unlikeTweet(creds, tweetId);
        } else {
          await XApiService.instance.likeTweet(creds, tweetId);
        }
      } else if (post.source == SnsService.bluesky) {
        final creds = account.blueskyCredentials;
        if (post.isLiked) {
          // For unlike we need the like URI - simplified: just toggle local
        } else {
          final postUri = _buildBlueskyUri(post);
          if (postUri != null) {
            await BlueskyApiService.instance.likePost(creds, postUri, '');
          }
        }
      }
    } catch (e) {
      // Revert on failure
      ref.read(feedProvider.notifier).updatePostEngagement(
            post.id,
            isLiked: post.isLiked,
            likeCount: post.likeCount,
          );
    }
  }

  Future<void> _handleRepost(Post post) async {
    final account = _getAccountForPost(post);
    if (account == null) return;

    ref.read(feedProvider.notifier).updatePostEngagement(
          post.id,
          isReposted: !post.isReposted,
          repostCount:
              post.isReposted ? post.repostCount - 1 : post.repostCount + 1,
        );

    try {
      if (post.source == SnsService.x) {
        final creds = account.xCredentials;
        final tweetId = post.id.replaceFirst('x_', '');
        if (post.isReposted) {
          await XApiService.instance.unretweet(creds, tweetId);
        } else {
          await XApiService.instance.retweet(creds, tweetId);
        }
      }
    } catch (e) {
      ref.read(feedProvider.notifier).updatePostEngagement(
            post.id,
            isReposted: post.isReposted,
            repostCount: post.repostCount,
          );
    }
  }

  Account? _getAccountForPost(Post post) {
    if (post.accountId == null) return null;
    return AccountStorageService.instance.getAccount(post.accountId!);
  }

  String? _buildBlueskyUri(Post post) {
    final account = _getAccountForPost(post);
    if (account == null) return null;
    final did = account.blueskyCredentials.did;
    final rkey = post.id.replaceFirst('bsky_', '');
    return 'at://$did/app.bsky.feed.post/$rkey';
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final settings = ref.watch(settingsProvider);
    final accounts = ref.watch(accountProvider);

    return Scaffold(
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            floating: true,
            snap: true,
            title: const Text(
              'OmniVerse',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.people_outline),
              tooltip: 'アカウント',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountsScreen()),
                );
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '設定',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ],
          ),
        ],
        body: _buildBody(context, feed, settings, accounts),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('投稿機能は今後実装予定です')),
          );
        },
        child: const Icon(Icons.edit),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    FeedState feed,
    SettingsState settings,
    List<Account> accounts,
  ) {
    if (accounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.rss_feed, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                'OmniVerse',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'アカウントを追加してタイムラインを取得しましょう',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountsScreen()),
                  );
                },
                icon: const Icon(Icons.person_add),
                label: const Text('アカウント追加'),
              ),
            ],
          ),
        ),
      );
    }

    if (!settings.isFetchingActive && feed.posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.rss_feed, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                'OmniVerse',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '設定画面でフェッチを有効にしてください',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                icon: const Icon(Icons.settings),
                label: const Text('設定を開く'),
              ),
            ],
          ),
        ),
      );
    }

    if (feed.isLoading && feed.posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(feedProvider.notifier).refresh(),
      child: Column(
        children: [
          // Error banner
          if (feed.error != null)
            MaterialBanner(
              content: Text(
                feed.error!,
                style: const TextStyle(fontSize: 13),
              ),
              leading: const Icon(Icons.error_outline, color: Colors.red),
              actions: [
                TextButton(
                  onPressed: () => ref.read(feedProvider.notifier).refresh(),
                  child: const Text('リトライ'),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(feedProvider.notifier).clearError(),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          // Post list
          Expanded(
            child: feed.posts.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(
                        child: Text(
                          '投稿が見つかりませんでした。\nしばらくお待ちください...',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: feed.posts.length + (feed.isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= feed.posts.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final post = feed.posts[index];
                      return PostCard(
                        post: post,
                        onTap: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, anim1, anim2) =>
                                  PostDetailScreen(post: post),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return SlideTransition(
                                  position: Tween(
                                    begin: const Offset(1, 0),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  )),
                                  child: child,
                                );
                              },
                            ),
                          );
                        },
                        onLike: () => _handleLike(post),
                        onRepost: () => _handleRepost(post),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
