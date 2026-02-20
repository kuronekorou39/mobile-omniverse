import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/sns_service.dart';
import '../widgets/sns_badge.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({
    super.key,
    required this.username,
    required this.handle,
    required this.service,
    this.avatarUrl,
  });

  final String username;
  final String handle;
  final SnsService service;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(handle),
      ),
      body: Column(
        children: [
          const SizedBox(height: 32),
          // Avatar
          CircleAvatar(
            radius: 48,
            backgroundImage: avatarUrl != null
                ? CachedNetworkImageProvider(avatarUrl!)
                : null,
            child: avatarUrl == null
                ? Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 36),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          // Username
          Text(
            username,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          // Handle + badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SnsBadge(service: service),
              const SizedBox(width: 8),
              Text(
                handle,
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(),
          const Expanded(
            child: Center(
              child: Text(
                'プロフィール詳細は今後実装予定です',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
