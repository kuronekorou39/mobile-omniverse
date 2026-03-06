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
  int _fontSizeIndex = 1;
  int _themeColorIndex = 0;
  bool _isMinimized = false;
  double? _savedX;
  double? _savedY;

  // フェッチタイマー状態
  int _fetchRemaining = 0;
  int _fetchTotal = 0;
  bool _isFetching = false;

  static const _widths = [180, 250, 360];
  static const _heights = [250, 400, 700];
  static const _labels = ['S', 'M', 'L'];
  static const _opacities = [0.3, 0.5, 0.7, 0.9, 1.0];
  static const _opacityLabels = ['30', '50', '70', '90', '100'];
  static const _fontSizes = [8.0, 10.0, 12.0];
  static const _fontSizeLabels = ['S', 'M', 'L'];

  static const _themeColors = [
    Color(0xFF1C1C1E), // ダーク
    Color(0xFF1A2A3A), // ブルー
    Color(0xFF2A1A3A), // パープル
    Color(0xFF1A2A2A), // ティール
  ];
  static const _themeAccentColors = [
    Colors.blue,
    Color(0xFF4A9EFF),
    Color(0xFF9A6AFF),
    Color(0xFF4ACFCF),
  ];

  Color get _bgColor => _themeColors[_themeColorIndex];
  Color get _accentColor => _themeAccentColors[_themeColorIndex];

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

  Future<void> _toggleMinimize() async {
    if (_isMinimized) {
      // 復元
      if (_savedX != null && _savedY != null) {
        await FlutterOverlayWindow.moveOverlay(
            OverlayPosition(_savedX!, _savedY!));
      }
      await FlutterOverlayWindow.resizeOverlay(
          _widths[_wIndex], _heights[_hIndex], false);
      setState(() => _isMinimized = false);
    } else {
      // 最小化: 現在位置を保存して右にスライド
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      _savedX = pos.x;
      _savedY = pos.y;
      await FlutterOverlayWindow.resizeOverlay(
          24, _heights[_hIndex], false);
      await FlutterOverlayWindow.moveOverlayByDelta(
          (_widths[_wIndex] - 24).toDouble(), 0);
      setState(() => _isMinimized = true);
    }
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
                      ? _accentColor.withAlpha(60)
                      : Colors.white.withAlpha(15),
                  border: Border.all(
                    color: i == current ? _accentColor : Colors.white24,
                    width: i == current ? 1 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: i == current
                        ? _accentColor.withAlpha(200)
                        : Colors.white54,
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

  Widget _buildLabeledSelector(
      IconData icon, List<String> labels, int current, ValueChanged<int> onSelect) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Icon(icon, color: Colors.white38, size: 16),
        ),
        for (int i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: i == current
                      ? _accentColor.withAlpha(60)
                      : Colors.white.withAlpha(15),
                  border: Border.all(
                    color: i == current ? _accentColor : Colors.white24,
                    width: i == current ? 1 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: i == current
                        ? _accentColor.withAlpha(200)
                        : Colors.white54,
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
                      ? _accentColor.withAlpha(60)
                      : Colors.white.withAlpha(15),
                  border: Border.all(
                    color: i == _opacityIndex ? _accentColor : Colors.white24,
                    width: i == _opacityIndex ? 1 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _opacityLabels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: i == _opacityIndex
                        ? _accentColor.withAlpha(200)
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

  Widget _buildThemeColorSelector() {
    return Row(
      children: [
        const SizedBox(
          width: 24,
          child: Icon(Icons.palette, color: Colors.white38, size: 16),
        ),
        for (int i = 0; i < _themeColors.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _themeColorIndex = i),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _themeColors[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color: i == _themeColorIndex
                      ? _themeAccentColors[i]
                      : Colors.white24,
                  width: i == _themeColorIndex ? 2 : 0.5,
                ),
              ),
              child: i == _themeColorIndex
                  ? Icon(Icons.check, size: 14, color: _themeAccentColors[i])
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFetchTimer() {
    final progress = _fetchTotal > 0 ? _fetchRemaining / _fetchTotal : 0.0;
    return SizedBox(
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
    );
  }

  Widget _buildSettingsPanel() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      children: [
        const SizedBox(height: 2),
        _buildSizeSelector(Icons.swap_horiz, _wIndex, _setWidth),
        const SizedBox(height: 8),
        _buildSizeSelector(Icons.swap_vert, _hIndex, _setHeight),
        const SizedBox(height: 8),
        _buildOpacitySelector(),
        const SizedBox(height: 8),
        _buildLabeledSelector(
          Icons.text_fields,
          _fontSizeLabels,
          _fontSizeIndex,
          (i) => setState(() => _fontSizeIndex = i),
        ),
        const SizedBox(height: 8),
        _buildThemeColorSelector(),
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
      color: _accentColor,
      backgroundColor: _bgColor.withAlpha(230),
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
            key: ValueKey(post.id),
            post: post,
            onShowDetail: () => _openPostDetail(post),
            fontSize: _fontSizes[_fontSizeIndex],
          );
        },
      ),
    );
  }

  Widget _buildMinimizedStrip() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleMinimize,
      child: Container(
        width: 24,
        decoration: BoxDecoration(
          color: _bgColor.withAlpha(220),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[700]!, width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chevron_left, color: _accentColor, size: 18),
            const SizedBox(height: 4),
            Icon(Icons.rss_feed, color: _accentColor, size: 14),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isMinimized) {
      return Material(
        color: Colors.transparent,
        child: _buildMinimizedStrip(),
      );
    }

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: _opacities[_opacityIndex],
          child: Container(
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _settingsOpen ? _accentColor : Colors.grey[700]!,
                width: _settingsOpen ? 1.5 : 0.5,
              ),
            ),
            child: Column(
              children: [
                // Header bar (ドラッグはネイティブ側で処理)
                Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: _settingsOpen
                          ? _accentColor.withAlpha(40)
                          : _bgColor.withAlpha(240),
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
                                  _settingsOpen ? Icons.close : Icons.tune,
                                  color: _settingsOpen
                                      ? _accentColor
                                      : Colors.white70,
                                  size: 14,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _settingsOpen ? '閉じる' : '設定',
                                  style: TextStyle(
                                    color: _settingsOpen
                                        ? _accentColor
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
                        // 最小化ボタン
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _toggleMinimize,
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.chevron_right,
                                color: Colors.white70, size: 16),
                          ),
                        ),
                        const SizedBox(width: 2),
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
