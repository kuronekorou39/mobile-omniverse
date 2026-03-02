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
  int _positionIndex = 0; // 0=top, 1=center, 2=bottom

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

  void _cyclePosition() {
    setState(() {
      _positionIndex = (_positionIndex + 1) % 3;
    });
    // Screen height approximation: move to top/center/bottom
    final ratio = View.of(context).devicePixelRatio;
    final screenH = View.of(context).physicalSize.height;
    final overlayH = 700 * ratio;
    final double y;
    switch (_positionIndex) {
      case 0:
        y = 0; // top
      case 1:
        y = (screenH - overlayH) / 2; // center
      default:
        y = screenH - overlayH; // bottom
    }
    FlutterOverlayWindow.moveOverlay(OverlayPosition(0, y / ratio));
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
            border: Border.all(color: Colors.grey[700]!, width: 0.5),
          ),
          child: Column(
            children: [
              // Header bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.vertical(
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
                    // Position toggle (top / center / bottom)
                    GestureDetector(
                      onTap: _cyclePosition,
                      child: Icon(
                        _positionIndex == 0
                            ? Icons.vertical_align_top
                            : _positionIndex == 1
                                ? Icons.vertical_align_center
                                : Icons.vertical_align_bottom,
                        color: Colors.white70,
                        size: 16,
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
                child: _posts.isEmpty
                    ? const Center(
                        child: Text(
                          '読み込み中...',
                          style: TextStyle(color: Colors.white54, fontSize: 10),
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
