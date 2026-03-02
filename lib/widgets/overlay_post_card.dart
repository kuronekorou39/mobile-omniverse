import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/sns_service.dart';
import 'sns_badge.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Initial avatar
              CircleAvatar(
                radius: 14,
                backgroundColor: post.source == SnsService.x
                    ? Colors.grey[700]
                    : const Color(0xFF0085FF),
                child: Text(
                  post.username.isNotEmpty
                      ? post.username[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Name + handle
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        post.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      post.handle,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              SnsBadge(service: post.source),
              const SizedBox(width: 4),
              Text(
                _formatTimestamp(post.timestamp),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          // Body
          Padding(
            padding: const EdgeInsets.only(left: 34, top: 2, bottom: 2),
            child: Text(
              post.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
          // Engagement counts
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Row(
              children: [
                const Icon(Icons.favorite_border,
                    size: 12, color: Colors.white38),
                const SizedBox(width: 2),
                Text(
                  '${post.likeCount}',
                  style: const TextStyle(fontSize: 10, color: Colors.white38),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.repeat, size: 12, color: Colors.white38),
                const SizedBox(width: 2),
                Text(
                  '${post.repostCount}',
                  style: const TextStyle(fontSize: 10, color: Colors.white38),
                ),
              ],
            ),
          ),
          Divider(height: 8, thickness: 0.5, color: Colors.grey[700]),
        ],
      ),
    );
  }
}
