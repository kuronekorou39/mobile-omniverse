import 'dart:async';
import 'dart:convert';

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
  final ScrollController _scrollController = ScrollController();
  bool _settingsOpen = false;
  bool _isLoadingMore = false;
  int _wIndex = 0;
  int _hIndex = 0;
  int _opacityIndex = 3;

  // フェッチタイマー状態
  int _fetchRemaining = 0;
  int _fetchTotal = 0;
  bool _isFetching = false;

  static const _widths = [180, 250, 360];
  static const _heights = [250, 400, 700];
  static const _labels = ['S', 'M', 'L'];
  static const _opacities = [0.3, 0.5, 0.7, 0.9, 1.0];
  static const _opacityLabels = ['30', '50', '70', '90', '100'];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _subscription = FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is String) {
        try {
          final decoded = jsonDecode(data);
          List<dynamic> postList;
          if (decoded is Map<String, dynamic>) {
            postList = decoded['posts'] as List<dynamic>? ?? [];
            final fetch = decoded['fetch'] as Map<String, dynamic>?;
            if (fetch != null) {
              _fetchRemaining = fetch['remaining'] as int? ?? 0;
              _fetchTotal = fetch['total'] as int? ?? 0;
              _isFetching = fetch['isFetching'] as bool? ?? false;
            }
          } else {
            postList = decoded as List<dynamic>;
          }
          final posts = postList
              .map((e) => Post.fromCache(e as Map<String, dynamic>))
              .toList();
          if (mounted) {
            setState(() {
              _posts = posts;
              _isLoadingMore = false;
            });
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      if (!_isLoadingMore && _posts.isNotEmpty) {
        setState(() => _isLoadingMore = true);
        FlutterOverlayWindow.shareData({"cmd": "loadMore"});
        // タイムアウトでリセット
        Future.delayed(const Duration(seconds: 15), () {
          if (mounted && _isLoadingMore) {
            setState(() => _isLoadingMore = false);
          }
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    await FlutterOverlayWindow.shareData({"cmd": "refresh"});
    // コマンド送信後、短いフィードバック表示で即戻る
    // 実データはメインアプリのフェッチ完了後に自動で届く
    await Future.delayed(const Duration(milliseconds: 1500));
  }

  Future<void> _openMainApp() async {
    await FlutterOverlayWindow.launchMainActivity();
  }

  Future<void> _openPostDetail(Post post) async {
    await FlutterOverlayWindow.openPostDetail(jsonEncode(post.toJson()));
  }

  Future<void> _toggleSettings() async {
    final opening = !_settingsOpen;
    await FlutterOverlayWindow.resizeOverlay(
        _widths[_wIndex], _heights[_hIndex], false);
    setState(() => _settingsOpen = opening);
  }

  Future<void> _setWidth(int index) async {
    await FlutterOverlayWindow.resizeOverlay(
        _widths[index], _heights[_hIndex], false);
    setState(() => _wIndex = index);
  }

  Future<void> _setHeight(int index) async {
    await FlutterOverlayWindow.resizeOverlay(
        _widths[_wIndex], _heights[index], false);
    setState(() => _hIndex = index);
  }

  Widget _buildSizeSelector(
      IconData icon, int current, ValueChanged<int> onSelect) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Icon(icon, color: Colors.white38, size: 16),
        ),
        for (int i = 0; i < _labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
                    fontSize: 11,
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
          child: Icon(Icons.opacity, color: Colors.white38, size: 16),
        ),
        for (int i = 0; i < _opacityLabels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _opacityIndex = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
                    fontSize: 10,
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

  Widget _buildFetchTimer() {
    final progress = _fetchTotal > 0 ? _fetchRemaining / _fetchTotal : 0.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: _isFetching
              ? const CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white54,
                )
              : CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 1.5,
                  color: Colors.blue,
                  backgroundColor: Colors.white12,
                ),
        ),
        const SizedBox(width: 3),
        Text(
          _isFetching ? '...' : '$_fetchRemaining',
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPanel() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: [
              const SizedBox(height: 2),
              _buildSizeSelector(Icons.swap_horiz, _wIndex, _setWidth),
              const SizedBox(height: 8),
              _buildSizeSelector(Icons.swap_vert, _hIndex, _setHeight),
              const SizedBox(height: 8),
              _buildOpacitySelector(),
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

  Widget _buildTimeline() {
    if (_posts.isEmpty) {
      return const Center(
        child: Text(
          '読み込み中...',
          style: TextStyle(color: Colors.white54, fontSize: 10),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: Colors.blue,
      backgroundColor: const Color(0xFF2C2C2E),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 2),
        itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return const Padding(
              padding: EdgeInsets.all(8),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white38,
                  ),
                ),
              ),
            );
          }
          final post = _posts[index];
          return OverlayPostCard(
            post: post,
            onShowDetail: () => _openPostDetail(post),
          );
        },
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
          opacity: _opacities[_opacityIndex],
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
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
                      Expanded(
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.drag_indicator,
                                  color: Colors.white24, size: 16),
                              const SizedBox(width: 4),
                              _buildFetchTimer(),
                            ],
                          ),
                        ),
                      ),
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
                      : _buildTimeline(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
