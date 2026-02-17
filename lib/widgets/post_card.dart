import 'package:flutter/material.dart';

import '../models/post.dart';
import 'sns_badge.dart';

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});

  final Post post;

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: post.avatarUrl != null
                      ? NetworkImage(post.avatarUrl!)
                      : null,
                  child: post.avatarUrl == null
                      ? Text(
                          post.username.isNotEmpty
                              ? post.username[0].toUpperCase()
                              : '?',
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.username,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          SnsBadge(service: post.source),
                        ],
                      ),
                      Text(
                        post.handle,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatTimestamp(post.timestamp),
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(post.body),
          ],
        ),
      ),
    );
  }
}
