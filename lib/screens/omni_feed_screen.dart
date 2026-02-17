import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/post_card.dart';

class OmniFeedScreen extends ConsumerWidget {
  const OmniFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);
    final settings = ref.watch(settingsProvider);

    if (!settings.isScrapingActive && feed.posts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.rss_feed, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Omni-Feed',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'X / Bluesky タブでログインし、\n設定画面でスクレイピングを有効にしてください',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(feedProvider.notifier).refresh(),
      child: feed.isLoading && feed.posts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : feed.posts.isEmpty
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
                  itemCount: feed.posts.length,
                  itemBuilder: (context, index) =>
                      PostCard(post: feed.posts[index]),
                ),
    );
  }
}
