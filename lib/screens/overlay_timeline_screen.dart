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
  double _opacity = 0.94;

  static const _widths = [180, 250, 360];
  static const _heights = [250, 400, 700];
  static const _labels = ['S', 'M', 'L'];

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
          width: 32,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ),
        for (int i = 0; i < _labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(i),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                style: TextStyle(
                  color: i == current ? Colors.blue[300] : Colors.white54,
                  fontSize: 11,
                  fontWeight:
                      i == current ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSettingsPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag hint
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.open_with, color: Colors.white24, size: 16),
              SizedBox(width: 4),
              Text(
                'ドラッグで移動可能',
                style: TextStyle(color: Colors.white30, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Width
          _buildSizeSelector('横幅', _wIndex, _setWidth),
          const SizedBox(height: 8),
          // Height
          _buildSizeSelector('縦幅', _hIndex, _setHeight),
          const SizedBox(height: 10),
          // Opacity
          Row(
            children: [
              const SizedBox(
                width: 32,
                child: Text(
                  '透明',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: Colors.blue[300],
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.blue[200],
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _opacity,
                    min: 0.3,
                    max: 1.0,
                    onChanged: (v) => setState(() => _opacity = v),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '${(_opacity * 100).round()}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Done button
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleSettings,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
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
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: _settingsOpen ? 1.0 : _opacity,
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
