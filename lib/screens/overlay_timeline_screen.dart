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
  int _themeModeIndex = 0; // 0=ダーク, 1=ライト, 2=システム
  bool _isMinimized = false;
  final Set<String> _expandedPostIds = {};
  final Set<String> _newPostIds = {};

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

  static const _accentColor = Colors.blue;

  bool get _isDark {
    if (_themeModeIndex == 0) return true;
    if (_themeModeIndex == 1) return false;
    // システム準拠
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  OverlayThemeColors get _theme =>
      _isDark ? OverlayThemeColors.dark : OverlayThemeColors.light;

  Color get _bgColor => _theme.bg;

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
            // Detect new posts for animation (skip initial load)
            if (_posts.isNotEmpty) {
              final oldIds = _posts.map((p) => p.id).toSet();
              for (final p in posts) {
                if (!oldIds.contains(p.id)) {
                  _newPostIds.add(p.id);
                }
              }
            }
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
      await FlutterOverlayWindow.restoreOverlay();
      setState(() => _isMinimized = false);
    } else {
      await FlutterOverlayWindow.minimizeOverlay(30);
      setState(() => _isMinimized = true);
    }
  }

  Widget _buildSizeSelector(
      IconData icon, int current, ValueChanged<int> onSelect) {
    return _buildLabeledSelector(icon, _labels, current, onSelect);
  }

  Widget _buildLabeledSelector(
      IconData icon, List<String> labels, int current, ValueChanged<int> onSelect) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Icon(icon, color: _theme.textQuaternary, size: 16),
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
                      : _theme.border.withAlpha(30),
                  border: Border.all(
                    color: i == current ? _accentColor : _theme.border,
                    width: i == current ? 1 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: i == current
                        ? _accentColor
                        : _theme.textTertiary,
                    fontSize: 11,
                    fontWeight:
                        i == current ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildOpacitySelector() {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Icon(Icons.opacity, color: _theme.textQuaternary, size: 16),
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
                      : _theme.border.withAlpha(30),
                  border: Border.all(
                    color: i == _opacityIndex ? _accentColor : _theme.border,
                    width: i == _opacityIndex ? 1 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _opacityLabels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: i == _opacityIndex
                        ? _accentColor
                        : _theme.textTertiary,
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
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildThemeModeSelector() {
    const modeLabels = ['ダーク', 'ライト', '自動'];
    const modeIcons = [Icons.dark_mode, Icons.light_mode, Icons.brightness_auto];
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Icon(Icons.contrast, color: _theme.textQuaternary, size: 16),
        ),
        for (int i = 0; i < modeLabels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _themeModeIndex = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: i == _themeModeIndex
                      ? _accentColor.withAlpha(60)
                      : _theme.border.withAlpha(30),
                  border: Border.all(
                    color: i == _themeModeIndex ? _accentColor : _theme.border,
                    width: i == _themeModeIndex ? 1 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    Icon(
                      modeIcons[i],
                      size: 14,
                      color: i == _themeModeIndex
                          ? _accentColor
                          : _theme.textTertiary,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      modeLabels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: i == _themeModeIndex
                            ? _accentColor
                            : _theme.textTertiary,
                        fontSize: 9,
                        fontWeight: i == _themeModeIndex
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFetchTimer() {
    final progress = _fetchTotal > 0 ? _fetchRemaining / _fetchTotal : 0.0;
    return SizedBox(
      width: 14,
      height: 14,
      child: _isFetching
          ? CircularProgressIndicator(
              strokeWidth: 1.5,
              color: _theme.textTertiary,
            )
          : CircularProgressIndicator(
              value: progress,
              strokeWidth: 1.5,
              color: _accentColor,
              backgroundColor: _theme.iconColor,
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
        _buildThemeModeSelector(),
      ],
    );
  }

  Widget _buildTimeline() {
    if (_posts.isEmpty) {
      return Center(
        child: Text(
          '読み込み中...',
          style: TextStyle(color: _theme.textTertiary, fontSize: 10),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: _accentColor,
      backgroundColor: _bgColor,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 2),
        itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _theme.textQuaternary,
                  ),
                ),
              ),
            );
          }
          final post = _posts[index];
          Widget card = OverlayPostCard(
            key: ValueKey(post.id),
            post: post,
            onShowDetail: () => _openPostDetail(post),
            fontSize: _fontSizes[_fontSizeIndex],
            theme: _theme,
            isExpanded: _expandedPostIds.contains(post.id),
            onToggleExpand: () {
              setState(() {
                if (_expandedPostIds.contains(post.id)) {
                  _expandedPostIds.remove(post.id);
                } else {
                  _expandedPostIds.add(post.id);
                }
              });
            },
          );
          // New post animation
          if (_newPostIds.contains(post.id)) {
            card = TweenAnimationBuilder<double>(
              key: ValueKey('anim_${post.id}'),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 300),
              onEnd: () {
                _newPostIds.remove(post.id);
              },
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: value,
                      child: child,
                    ),
                  ),
                );
              },
              child: card,
            );
          }
          return card;
        },
      ),
    );
  }

  Widget _buildMinimizedStrip() {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleMinimize,
        child: Container(
          width: 30,
          height: 80,
          decoration: BoxDecoration(
            color: _bgColor.withAlpha(220),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(12),
            ),
            border: Border.all(color: _theme.border, width: 0.5),
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
                color: _settingsOpen ? _accentColor : _theme.border,
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
                          : _theme.headerBg,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _openMainApp,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.open_in_new,
                                color: _theme.text, size: 16),
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
                                      : _theme.text,
                                  size: 14,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _settingsOpen ? '閉じる' : '設定',
                                  style: TextStyle(
                                    color: _settingsOpen
                                        ? _accentColor
                                        : _theme.textTertiary,
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
                                Icon(Icons.drag_indicator,
                                    color: _theme.iconColor, size: 16),
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
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.chevron_right,
                                color: _theme.text, size: 16),
                          ),
                        ),
                        const SizedBox(width: 2),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            await FlutterOverlayWindow.closeOverlay();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.close,
                                color: _theme.text, size: 16),
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
