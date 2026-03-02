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
  bool _moveMode = false;

  static const _overlayW = 360;
  static const _overlayH = 700;

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
        '-a', 'android.intent.action.MAIN',
        '-c', 'android.intent.category.LAUNCHER',
        '-n', 'com.omniverse.mobile_omniverse/.MainActivity',
        '-f', '0x10000000',
      ]);
    } catch (_) {}
  }

  Future<void> _toggleMoveMode() async {
    final newMode = !_moveMode;
    await FlutterOverlayWindow.resizeOverlay(
      _overlayW,
      _overlayH,
      newMode,
    );
    setState(() => _moveMode = newMode);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF01C1C1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _moveMode ? Colors.blue : Colors.grey[700]!,
              width: _moveMode ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              // Header bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: _moveMode
                      ? const Color(0xFF1A3A5C)
                      : const Color(0xFF2C2C2E),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _openMainApp,
                      child: const Icon(Icons.open_in_new,
                          color: Colors.white70, size: 16),
                    ),
                    const SizedBox(width: 6),
                    // Move mode toggle
                    GestureDetector(
                      onTap: _toggleMoveMode,
                      child: Icon(
                        _moveMode ? Icons.lock_open : Icons.drag_indicator,
                        color: _moveMode ? Colors.blue[300] : Colors.white70,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (_moveMode)
                      Text(
                        '移動モード',
                        style: TextStyle(
                          color: Colors.blue[300],
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const Spacer(),
                    Text(
                      '${_posts.length}件',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () async {
                        await FlutterOverlayWindow.closeOverlay();
                      },
                      child: const Icon(Icons.close,
                          color: Colors.white70, size: 16),
                    ),
                  ],
                ),
              ),
              // Post list
              Expanded(
                child: _moveMode
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_with,
                                color: Colors.white24, size: 40),
                            SizedBox(height: 8),
                            Text(
                              'ドラッグで移動\n完了したらもう一度タップ',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      )
                    : _posts.isEmpty
                        ? const Center(
                            child: Text(
                              '読み込み中...',
                              style:
                                  TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 2),
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
