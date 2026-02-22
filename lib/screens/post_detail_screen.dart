import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' as share_plus;

import '../utils/image_headers.dart';
import '../models/account.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_api_service.dart';
import '../widgets/post_card.dart';
import '../widgets/post_media.dart';
import '../widgets/sns_badge.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final Post post;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  List<Post> _replies = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReplies();
  }

  Future<void> _loadReplies() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final account = _getAccount();
      if (account == null) {
        setState(() {
          _isLoading = false;
          _error = 'アカウント情報が見つかりません';
        });
        return;
      }

      List<Post> posts;
      if (widget.post.source == SnsService.x) {
        final tweetId = widget.post.id.replaceFirst('x_', '');
        posts = await XApiService.instance.getTweetDetail(
          account.xCredentials,
          tweetId,
          accountId: account.id,
        );
      } else {
        // Bluesky
        final rkey = widget.post.id.replaceFirst('bsky_', '');
        final did = account.blueskyCredentials.did;
        final postUri = 'at://$did/app.bsky.feed.post/$rkey';
        posts = await BlueskyApiService.instance.getPostThread(
          account.blueskyCredentials,
          postUri,
          accountId: account.id,
        );
      }

      // Separate the main post from replies
      final replies = posts
          .where((p) => p.id != widget.post.id)
          .toList();

      setState(() {
        _replies = replies;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'リプライの取得に失敗しました: $e';
      });
    }
  }

  Account? _getAccount() {
    if (widget.post.accountId == null) return null;
    return AccountStorageService.instance.getAccount(widget.post.accountId!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('投稿詳細'),
        actions: [
          if (widget.post.permalink != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () {
                share_plus.Share.share(widget.post.permalink!);
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReplies,
        child: ListView(
          children: [
            // Main post (expanded)
            _buildMainPost(context),
            const Divider(height: 1),

            // Replies section
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _loadReplies,
                      child: const Text('リトライ'),
                    ),
                  ],
                ),
              )
            else if (_replies.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'リプライはありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  'リプライ (${_replies.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              ..._replies.map(
                (reply) => PostCard(
                  post: reply,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(post: reply),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildMainPost(BuildContext context) {
    final post = widget.post;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author header
          Row(
            children: [
              Hero(
                tag: 'avatar_${post.id}',
                child: CircleAvatar(
                  radius: 24,
                  backgroundImage: post.avatarUrl != null
                      ? CachedNetworkImageProvider(post.avatarUrl!, headers: kImageHeaders)
                      : null,
                  child: post.avatarUrl == null
                      ? Text(post.username.isNotEmpty
                          ? post.username[0].toUpperCase()
                          : '?')
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            post.username,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SnsBadge(service: post.source),
                      ],
                    ),
                    Text(
                      post.handle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Full text with tappable links
          LinkedText(
            text: post.body,
            style: const TextStyle(fontSize: 16, height: 1.5),
            selectable: true,
          ),

          // Images (shared widget - not PostCard!)
          if (post.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            PostImageGrid(imageUrls: post.imageUrls),
          ],

          // Video
          if (post.videoUrl != null && post.videoThumbnailUrl != null) ...[
            const SizedBox(height: 12),
            PostVideoThumbnail(
              videoUrl: post.videoUrl!,
              thumbnailUrl: post.videoThumbnailUrl!,
            ),
          ],

          const SizedBox(height: 12),

          // Timestamp
          Text(
            _formatFullTimestamp(post.timestamp),
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),

          const SizedBox(height: 12),
          const Divider(),

          // Engagement counts
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _buildCountLabel(post.replyCount, 'リプライ'),
                const SizedBox(width: 24),
                _buildCountLabel(post.repostCount, 'リポスト'),
                const SizedBox(width: 24),
                _buildCountLabel(post.likeCount, 'いいね'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountLabel(int count, String label) {
    return Row(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ],
    );
  }

  String _formatFullTimestamp(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
