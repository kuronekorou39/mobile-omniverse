import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../models/post.dart';
import '../widgets/overlay_post_card.dart';

class OverlayTimelineScreen extends StatefulWidget {
  const OverlayTimelineScreen({super.key});

  @override
  State<OverlayTimelineScreen> createState() => _OverlayTimelineScreenState();
}

class _OverlayTimelineScreenState extends State<OverlayTimelineScreen> {
  List<Post> _posts = [];
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is String) {
        try {
          final list = jsonDecode(data) as List<dynamic>;
          final posts = list
              .map((e) => Post.fromCache(e as Map<String, dynamic>))
              .toList();
          if (mounted) {
            setState(() => _posts = posts);
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _openMainApp() async {
    try {
      await Process.run('am', [
        'start',
        '-n',
        'com.omniverse.mobile_omniverse/.MainActivity',
        '--activity-brought-to-front',
      ]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF01C1C1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[700]!, width: 0.5),
          ),
          child: Column(
            children: [
              // Header bar (drag handle)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    // Open main app
                    GestureDetector(
                      onTap: _openMainApp,
                      child: const Icon(Icons.open_in_new,
                          color: Colors.white70, size: 18),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'OmniVerse',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '${_posts.length}件',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        await FlutterOverlayWindow.closeOverlay();
                      },
                      child: const Icon(Icons.close,
                          color: Colors.white70, size: 20),
                    ),
                  ],
                ),
              ),
              // Post list
              Expanded(
                child: _posts.isEmpty
                    ? const Center(
                        child: Text(
                          'タイムラインを読み込み中...',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 4),
                        itemCount: _posts.length,
                        itemBuilder: (context, index) {
                          return OverlayPostCard(post: _posts[index]);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
