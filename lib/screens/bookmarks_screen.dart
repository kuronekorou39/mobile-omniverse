import 'package:flutter/material.dart';

import '../services/bookmark_service.dart';
import '../widgets/post_card.dart';
import 'post_detail_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  @override
  Widget build(BuildContext context) {
    final bookmarks = BookmarkService.instance.bookmarks;

    return Scaffold(
      appBar: AppBar(title: const Text('ブックマーク')),
      body: bookmarks.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bookmark_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'ブックマークはありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '投稿のブックマークアイコンをタップして保存できます',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: bookmarks.length,
              itemBuilder: (context, index) {
                final post = bookmarks[index];
                return Dismissible(
                  key: ValueKey(post.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await BookmarkService.instance.toggle(post);
                    setState(() {});
                  },
                  child: PostCard(
                    post: post,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PostDetailScreen(post: post),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
