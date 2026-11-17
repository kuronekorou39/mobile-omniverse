import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/account_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_snackbar.dart';
import 'background_job_indicator.dart';

/// ヘッダーに置く小さなボタンの共通の大きさ
const headerButtonConstraints = BoxConstraints(minWidth: 40, minHeight: 40);

typedef HeaderButtonItem = ({
  String key,
  IconData icon,
  String tooltip,
  VoidCallback onPressed,
});

/// 表示切り替えボタンの定義（ヘッダー / クイック設定パネル共通）
List<HeaderButtonItem> buildHeaderButtonItems(
    SettingsState settings, SettingsNotifier notifier) {
  final items = <HeaderButtonItem>[];

  if (settings.appBarButtons.contains('sensitive')) {
    final (icon, tooltip) = switch (settings.sensitiveMode) {
      SensitiveMode.show => (Icons.blur_off, 'モザイク: OFF'),
      SensitiveMode.hide => (Icons.blur_on, 'モザイク: センシティブのみ'),
      SensitiveMode.hideAll => (Icons.blur_circular, 'モザイク: 全て隠す'),
    };
    items.add((
      key: 'sensitive',
      icon: icon,
      tooltip: tooltip,
      onPressed: () => notifier.cycleSensitiveMode(),
    ));
  }

  if (settings.appBarButtons.contains('userInfo')) {
    final isHiding = settings.hideUserInfo;
    items.add((
      key: 'userInfo',
      icon: isHiding ? Icons.face_retouching_off : Icons.face_retouching_natural,
      tooltip: isHiding ? '匿名モード: ON' : '匿名モード: OFF',
      onPressed: () => notifier.setHideUserInfo(!isHiding),
    ));
  }

  if (settings.appBarButtons.contains('wakelock')) {
    final isOn = settings.keepScreenOn;
    items.add((
      key: 'wakelock',
      icon: isOn ? Icons.lock : Icons.lock_open,
      tooltip: isOn ? 'スリープ防止: ON' : 'スリープ防止: OFF',
      onPressed: () => notifier.setKeepScreenOn(!isOn),
    ));
  }

  if (settings.appBarButtons.contains('retweet')) {
    final isHiding = settings.hideAllRetweets;
    items.add((
      key: 'retweet',
      icon: isHiding ? Icons.repeat_on : Icons.repeat,
      tooltip: isHiding ? 'RT非表示: ON' : 'RT非表示: OFF',
      onPressed: () => notifier.setHideAllRetweets(!isHiding),
    ));
  }

  if (settings.appBarButtons.contains('engagement')) {
    final isHiding = settings.hideEngagement;
    items.add((
      key: 'engagement',
      icon: isHiding ? Icons.chat_bubble : Icons.chat_bubble_outline,
      tooltip: isHiding ? 'アクション非表示: ON' : 'アクション非表示: OFF',
      onPressed: () => notifier.setHideEngagement(!isHiding),
    ));
  }

  return items;
}

/// 取得タイマーを出す状態か
bool _showFetchTimer(WidgetRef ref) {
  final hasAccounts = ref.watch(accountProvider.select((a) => a.isNotEmpty));
  return hasAccounts &&
      ref.watch(settingsProvider
          .select((s) => s.isFetchingActive && s.showFetchTimer));
}

/// 取得タイマーと、裏で走っている収集の進み。
///
/// 縦画面ではヘッダーの切り替えボタンの隣、横に広い画面では右上の隅に置く。
class FeedIndicators extends ConsumerWidget {
  const FeedIndicators({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showFetchTimer(ref)) const FetchTimerIndicator(),
        // 裏で走っている収集は、この画面からは見えないまま何時間も続く。
        // 動いていることと、その進みをここに出す
        const BackgroundJobIndicator(),
      ],
    );
  }
}

/// タイムラインの表示切り替え。
///
/// 縦画面ではヘッダーの左に横並びで置き、取得の進みを隣に続ける。
/// 横に広い画面では左の列に縦並びで置く（進みは右上の隅に分かれる）。
class FeedQuickButtons extends ConsumerWidget {
  const FeedQuickButtons({super.key, this.axis = Axis.horizontal});

  final Axis axis;

  /// 縦に並べるとき、これより低い画面では切り替えをメニューにまとめる。
  /// スマホの横向きは高さが 400 前後しかなく、全部は並ばない
  static const _verticalGroupMaxHeight = 600.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final items =
        buildHeaderButtonItems(settings, ref.read(settingsProvider.notifier));

    // 取得タイマーは常に独立表示（メニューに入れない）
    final showTimer = _showFetchTimer(ref);

    final bool group;
    if (axis == Axis.horizontal) {
      // タイマー表示時はボタン枠を1つ使うため、残り2個以上でまとめる
      group = items.length >= (showTimer ? 2 : 3);
    } else {
      group = items.length >= 2 &&
          MediaQuery.sizeOf(context).height < _verticalGroupMaxHeight;
    }

    return Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (group)
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.more_vert, size: 20),
              constraints: headerButtonConstraints,
              padding: EdgeInsets.zero,
              onPressed: () => _showPanel(context),
            ),
          )
        else
          for (final item in items)
            IconButton(
              icon: Icon(item.icon, size: 20),
              tooltip: item.tooltip,
              onPressed: item.onPressed,
              constraints: headerButtonConstraints,
              padding: EdgeInsets.zero,
            ),
        if (axis == Axis.horizontal) const FeedIndicators(),
      ],
    );
  }

  void _showPanel(BuildContext buttonContext) {
    final Offset anchor;
    if (axis == Axis.horizontal) {
      anchor = Offset(
        8,
        MediaQuery.of(buttonContext).padding.top + kToolbarHeight,
      );
    } else {
      // 縦の列ではボタンのすぐ右に出す
      final box = buttonContext.findRenderObject()! as RenderBox;
      anchor = box.localToGlobal(Offset(box.size.width + 4, 0));
    }
    showDialog(
      context: buttonContext,
      barrierColor: Colors.black26,
      // 位置は画面の座標で渡している。安全領域で中身をずらされると合わない
      useSafeArea: false,
      builder: (_) => _QuickSettingsPanel(anchor: anchor),
    );
  }
}

/// 次の取得までの残りを輪で示す。未表示の投稿があれば件数を重ねる。
class FetchTimerIndicator extends ConsumerStatefulWidget {
  const FetchTimerIndicator({super.key});

  @override
  ConsumerState<FetchTimerIndicator> createState() =>
      _FetchTimerIndicatorState();
}

class _FetchTimerIndicatorState extends ConsumerState<FetchTimerIndicator> {
  /// 残り秒数は FeedNotifier が持っている。ここは描き直すだけ
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total =
        ref.watch(settingsProvider.select((s) => s.fetchIntervalSeconds));
    final pendingCount =
        ref.watch(feedProvider.select((f) => f.pendingCount));
    final remaining =
        ref.read(feedProvider.notifier).remainingSeconds.clamp(0, total);
    final progress = total > 0 ? remaining / total : 0.0;

    // IconButtonと同じconstraints/paddingで間隔を統一
    return ConstrainedBox(
      constraints: headerButtonConstraints,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: remaining == 0
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : CircularProgressIndicator(
                        value: progress.toDouble(),
                        strokeWidth: 2,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
              ),
              if (pendingCount > 0)
                Center(
                  child: Text(
                    '+$pendingCount',
                    style: TextStyle(
                      fontSize: 9,
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 表示切り替えをまとめたパネル（項目をタップしても閉じない）
class _QuickSettingsPanel extends ConsumerWidget {
  const _QuickSettingsPanel({required this.anchor});

  /// パネルの左上を置く画面上の位置
  final Offset anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final items = buildHeaderButtonItems(settings, notifier);

    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      // 横向きは縦が狭く、1 列だと画面の下にはみ出す。入りきらないときは
      // 列を増やして、スクロールせずに全部押せるようにする
      final room = constraints.maxHeight - pad.top - pad.bottom - _margin * 2;
      final perColumn = (room / _itemHeight).floor().clamp(1, items.length);
      final columns = (items.length / perColumn).ceil();
      final rows = (items.length / columns).ceil();

      Widget tile(HeaderButtonItem item) => InkWell(
            onTap: item.onPressed,
            child: SizedBox(
              height: _itemHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(item.icon, size: 20),
                    const SizedBox(width: 12),
                    Text(item.tooltip, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          );

      return CustomSingleChildLayout(
        delegate: _PanelLayout(anchor: anchor, padding: pad),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++)
                  IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in items.skip(c * rows).take(rows))
                          tile(item),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }

  static const _itemHeight = 44.0;
  static const _margin = 8.0;
}

/// パネルをボタンの横に置く。画面の下に入りきらなければ上へずらす
class _PanelLayout extends SingleChildLayoutDelegate {
  _PanelLayout({required this.anchor, required this.padding});

  final Offset anchor;
  final EdgeInsets padding;

  static const _margin = _QuickSettingsPanel._margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(Size(
      constraints.maxWidth - anchor.dx - padding.right - _margin,
      constraints.maxHeight - padding.top - padding.bottom - _margin * 2,
    ));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxY = size.height - padding.bottom - _margin - childSize.height;
    var y = anchor.dy;
    if (y > maxY) y = maxY;
    if (y < padding.top + _margin) y = padding.top + _margin;
    return Offset(anchor.dx, y);
  }

  @override
  bool shouldRelayout(_PanelLayout old) =>
      anchor != old.anchor || padding != old.padding;
}

/// タイムラインを小窓で出すボタン（Android のみ）
class OverlayLaunchButton extends ConsumerStatefulWidget {
  const OverlayLaunchButton({super.key});

  @override
  ConsumerState<OverlayLaunchButton> createState() =>
      _OverlayLaunchButtonState();
}

class _OverlayLaunchButtonState extends ConsumerState<OverlayLaunchButton> {
  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.picture_in_picture_alt, size: 20),
      tooltip: 'オーバーレイ',
      onPressed: () => _launchOverlay(ref.read(feedProvider)),
      constraints: headerButtonConstraints,
      padding: EdgeInsets.zero,
    );
  }

  /// オーバーレイ権限の付与手順を案内するガイドを表示。
  /// 設定画面で権限が付与された場合 true を返す。
  Future<bool?> _showOverlayPermissionGuide() {
    return showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'オーバーレイ権限が必要です',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'ストア外アプリは「制限付き設定」の解除が必要です。',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text('1. 設定 → アプリ → OmniVerse を選択',
                  style: TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              const Text('2. 右上の「⋮」メニュー →「制限付き設定を許可」',
                  style: TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              const Text('3. PIN / 生体認証で確認',
                  style: TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              const Text('4. 下のボタンから権限を ON にする',
                  style: TextStyle(fontSize: 14)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.settings),
                  label: const Text('オーバーレイ権限の設定を開く'),
                  onPressed: () async {
                    if (Platform.isAndroid) await FlutterOverlayWindow.requestPermission();
                    final granted =
                        Platform.isAndroid ? await FlutterOverlayWindow.isPermissionGranted() : false;
                    if (ctx.mounted) Navigator.of(ctx).pop(granted);
                  },
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchOverlay(FeedState feed) async {
    var granted = Platform.isAndroid ? await FlutterOverlayWindow.isPermissionGranted() : false;
    if (!granted) {
      if (!mounted) return;
      final result = await _showOverlayPermissionGuide();
      if (result == true) {
        granted = Platform.isAndroid ? await FlutterOverlayWindow.isPermissionGranted() : false;
      }
      if (!granted) return;
    }

    final isActive = Platform.isAndroid ? await FlutterOverlayWindow.isActive() : false;
    if (isActive) {
      if (Platform.isAndroid) await FlutterOverlayWindow.closeOverlay();
      ref.read(feedProvider.notifier).setOverlayActive(false);
      return;
    }

    try {
      // 保存済みのオーバーレイサイズ設定を読み込み
      const widths = [180, 250, 360];
      const heights = [250, 400, 700];
      final prefs = await SharedPreferences.getInstance();
      final wIndex = (prefs.getInt('overlay_wIndex') ?? 0).clamp(0, 2);
      final hIndex = (prefs.getInt('overlay_hIndex') ?? 0).clamp(0, 2);
      if (Platform.isAndroid) {
        await FlutterOverlayWindow.showOverlay(
          height: heights[hIndex],
          width: widths[wIndex],
          enableDrag: false,
          overlayTitle: 'OmniVerse',
          flag: OverlayFlag.defaultFlag,
          positionGravity: PositionGravity.none,
        );
      }

      final posts = feed.posts.take(100).map((p) => p.toJson()).toList();
      final settings = ref.read(settingsProvider);
      if (Platform.isAndroid) {
        await FlutterOverlayWindow.shareData(jsonEncode({
          'posts': posts,
          'fetch': {
            'remaining': 0,
            'total': settings.fetchIntervalSeconds,
            'isFetching': ref.read(feedProvider).isFetching,
          },
          'showFetchTimer': settings.showFetchTimer,
        }));
      }

      ref.read(feedProvider.notifier).setOverlayActive(true);

      // ホーム画面に戻る（Activityを破棄せずバックグラウンドへ）
      if (mounted && Platform.isAndroid) {
        await FlutterOverlayWindow.moveToBackground();
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'オーバーレイを開けませんでした: ${shortError(e)}',
          type: SnackType.error);
    }
  }
}
