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
  bool _settingsOpen = false;
  int _wIndex = 0;
  int _hIndex = 0;
  int _opacityIndex = 3;

  static const _widths = [180, 250, 360];
  static const _heights = [250, 400, 700];
  static const _labels = ['S', 'M', 'L'];
  static const _opacities = [0.3, 0.5, 0.7, 0.9, 1.0];
  static const _opacityLabels = ['30', '50', '70', '90', '100'];

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

  Future<void> _toggleSettings() async {
    final opening = !_settingsOpen;
    await FlutterOverlayWindow.resizeOverlay(
        _widths[_wIndex], _heights[_hIndex], opening);
    setState(() => _settingsOpen = opening);
  }

  Future<void> _setWidth(int index) async {
    await FlutterOverlayWindow.resizeOverlay(
        _widths[index], _heights[_hIndex], _settingsOpen);
    setState(() => _wIndex = index);
  }

  Future<void> _setHeight(int index) async {
    await FlutterOverlayWindow.resizeOverlay(
        _widths[_wIndex], _heights[index], _settingsOpen);
    setState(() => _hIndex = index);
  }

  Widget _buildSizeSelector(
      String label, int current, ValueChanged<int> onSelect) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ),
        for (int i = 0; i < _labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: i == current
                      ? Colors.blue.withAlpha(60)
                      : Colors.white.withAlpha(15),
                  border: Border.all(
                    color: i == current ? Colors.blue : Colors.white24,
                    width: i == current ? 1 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: i == current ? Colors.blue[300] : Colors.white54,
                    fontSize: 10,
                    fontWeight:
                        i == current ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOpacitySelector() {
    return Row(
      children: [
        const SizedBox(
          width: 24,
          child: Text(
            '透過',
            style: TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ),
        for (int i = 0; i < _opacityLabels.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _opacityIndex = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: i == _opacityIndex
                      ? Colors.blue.withAlpha(60)
                      : Colors.white.withAlpha(15),
                  border: Border.all(
                    color: i == _opacityIndex ? Colors.blue : Colors.white24,
                    width: i == _opacityIndex ? 1 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _opacityLabels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: i == _opacityIndex
                        ? Colors.blue[300]
                        : Colors.white54,
                    fontSize: 9,
                    fontWeight: i == _opacityIndex
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPreview() {
    final opacity = _opacities[_opacityIndex];
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xF01C1C1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[800]!, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.grey[600],
                  child: const Text('U',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text('ユーザー名',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10),
                      maxLines: 1),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('1m',
                    style: TextStyle(color: Colors.white30, fontSize: 9)),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 24, top: 1),
              child: Text(
                'これは表示サンプルです。この透明度で投稿が表示されます。',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white70, fontSize: 10, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: [
              // Drag hint
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.open_with, color: Colors.white24, size: 14),
                  SizedBox(width: 4),
                  Text('ドラッグで移動可能',
                      style: TextStyle(color: Colors.white30, fontSize: 9)),
                ],
              ),
              const SizedBox(height: 8),
              _buildSizeSelector('横', _wIndex, _setWidth),
              const SizedBox(height: 6),
              _buildSizeSelector('縦', _hIndex, _setHeight),
              const SizedBox(height: 6),
              _buildOpacitySelector(),
              const SizedBox(height: 8),
              const Text('プレビュー',
                  style: TextStyle(color: Colors.white38, fontSize: 9)),
              const SizedBox(height: 4),
              _buildPreview(),
            ],
          ),
        ),
        // Done button pinned at bottom
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleSettings,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(40),
                border: Border.all(color: Colors.blue, width: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '完了',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: _settingsOpen ? 1.0 : _opacities[_opacityIndex],
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xF01C1C1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _settingsOpen ? Colors.blue : Colors.grey[700]!,
                width: _settingsOpen ? 1.5 : 0.5,
              ),
            ),
            child: Column(
              children: [
                // Header bar
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _settingsOpen
                        ? const Color(0xFF1A3A5C)
                        : const Color(0xFF2C2C2E),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openMainApp,
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.open_in_new,
                              color: Colors.white70, size: 16),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleSettings,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tune,
                                color: _settingsOpen
                                    ? Colors.blue[300]
                                    : Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _settingsOpen ? '設定中' : '設定',
                                style: TextStyle(
                                  color: _settingsOpen
                                      ? Colors.blue[300]
                                      : Colors.white54,
                                  fontSize: 10,
                                  fontWeight: _settingsOpen
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (!_settingsOpen)
                        Text(
                          '${_posts.length}件',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                          ),
                        ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          await FlutterOverlayWindow.closeOverlay();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.close,
                              color: Colors.white70, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: _settingsOpen
                      ? _buildSettingsPanel()
                      : _posts.isEmpty
                          ? const Center(
                              child: Text(
                                '読み込み中...',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 10),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(top: 2),
                              itemCount: _posts.length,
                              itemBuilder: (context, index) {
                                return OverlayPostCard(
                                    post: _posts[index]);
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
