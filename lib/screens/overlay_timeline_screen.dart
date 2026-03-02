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

  // Drag: integer base position (dp) + fractional accumulator
  int _baseX = 0;
  int _baseY = 0;
  double _accumX = 0;
  double _accumY = 0;
  bool _posReady = false;

  // Overlay size in dp (must match showOverlay call)
  static const _overlayW = 360;
  static const _overlayH = 700;

  @override
  void initState() {
    super.initState();
    _initPosition();
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

  Future<void> _initPosition() async {
    try {
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      _baseX = pos.x.round();
      _baseY = pos.y.round();
      _posReady = true;
    } catch (_) {
      _posReady = true;
    }
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

  void _onDragStart(DragStartDetails details) {
    _accumX = 0;
    _accumY = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_posReady) return;

    _accumX += details.delta.dx;
    _accumY += details.delta.dy;

    // Screen bounds (dp)
    final view = View.of(context);
    final screenW = view.physicalSize.width / view.devicePixelRatio;
    final screenH = view.physicalSize.height / view.devicePixelRatio;

    var newX = _baseX + _accumX.round();
    var newY = _baseY + _accumY.round();

    // Clamp to screen edges
    newX = newX.clamp(0, (screenW - _overlayW).toInt().clamp(0, 9999));
    newY = newY.clamp(0, (screenH - _overlayH).toInt().clamp(0, 9999));

    FlutterOverlayWindow.moveOverlay(
      OverlayPosition(newX.toDouble(), newY.toDouble()),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    // Commit position
    final view = View.of(context);
    final screenW = view.physicalSize.width / view.devicePixelRatio;
    final screenH = view.physicalSize.height / view.devicePixelRatio;

    _baseX = (_baseX + _accumX.round())
        .clamp(0, (screenW - _overlayW).toInt().clamp(0, 9999));
    _baseY = (_baseY + _accumY.round())
        .clamp(0, (screenH - _overlayH).toInt().clamp(0, 9999));
    _accumX = 0;
    _accumY = 0;
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
              // Header bar — drag to move
              GestureDetector(
                onPanStart: _onDragStart,
                onPanUpdate: _onDragUpdate,
                onPanEnd: _onDragEnd,
                child: Container(
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
                      // Drag handle
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 32,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white30,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
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
