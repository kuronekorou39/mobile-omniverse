import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/sns_service.dart';

class OverlayPostCard extends StatelessWidget {
  const OverlayPostCard({super.key, required this.post});

  final Post post;

  String _formatTimestamp(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${timestamp.month}/${timestamp.day}';
  }

  @override
  Widget build(BuildContext context) {
    final sourceColor = post.source == SnsService.x
        ? Colors.grey[600]!
        : const Color(0xFF0085FF);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name + timestamp
          Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: sourceColor,
                backgroundImage: post.avatarUrl != null
                    ? NetworkImage(post.avatarUrl!)
                    : null,
                onBackgroundImageError:
                    post.avatarUrl != null ? (_, __) {} : null,
                child: post.avatarUrl == null
                    ? Text(
                        post.username.isNotEmpty
                            ? post.username[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  post.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // SNS indicator (dot instead of badge to save space)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: sourceColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _formatTimestamp(post.timestamp),
                style: const TextStyle(color: Colors.white30, fontSize: 9),
              ),
            ],
          ),
          // Body
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 1, bottom: 1),
            child: Text(
              post.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                height: 1.3,
              ),
            ),
          ),
          // Engagement (compact)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Row(
              children: [
                const Icon(Icons.favorite_border,
                    size: 9, color: Colors.white24),
                const SizedBox(width: 2),
                Text(
                  '${post.likeCount}',
                  style: const TextStyle(fontSize: 8, color: Colors.white24),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.repeat, size: 9, color: Colors.white24),
                const SizedBox(width: 2),
                Text(
                  '${post.repostCount}',
                  style: const TextStyle(fontSize: 8, color: Colors.white24),
                ),
              ],
            ),
          ),
          Divider(height: 6, thickness: 0.3, color: Colors.grey[800]),
        ],
      ),
    );
  }
}
