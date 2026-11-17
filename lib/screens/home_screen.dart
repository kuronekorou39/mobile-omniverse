import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/account_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/notification_badge_provider.dart';
import '../services/account_storage_service.dart';
import '../services/block_scan_service.dart';
import '../services/follow_capture_job_service.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding/timeline_style_sheet.dart';
import '../widgets/compose_queue_banner.dart';
import '../widgets/count_badge.dart';
import '../widgets/feed_header_buttons.dart';
import '../widgets/home_rail.dart';
import 'accounts_screen.dart';
import 'follow_capture_screen.dart';
import 'notifications_screen.dart';
import 'omni_feed_screen.dart';
import 'settings_screen.dart';
import 'user_search_screen.dart';

/// タブの中で何枚の画面が積まれているかを数える。
/// 左の列のボタンは、タブの最初の画面にいるときだけ出す
class _TabDepthObserver extends NavigatorObserver {
  _TabDepthObserver(this.onChanged);

  final VoidCallback onChanged;
  int _pages = 0;

  bool get atRoot => _pages <= 1;

  // 下から出るシートは数えない（開いている間に列のボタンが消えてしまう）
  void _add(Route<dynamic>? route, int delta) {
    if (route is! PageRoute) return;
    _pages += delta;
    onChanged();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route, 1);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route, -1);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route, -1);
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // アカウントがなければアカウントタブ、あればタイムラインタブ
  int _currentIndex = AccountStorageService.instance.accounts.isEmpty ? 0 : 1;

  /// タイムラインタブを再タップ時にトップへスクロールするためのコールバック
  VoidCallback? onTimelineTap;

  /// 各タブのNavigatorキー
  final _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  late final _depthObservers = [
    for (var i = 0; i < 3; i++) _TabDepthObserver(_onTabDepthChanged),
  ];

  /// 画面の積み下ろしはビルドの最中にも起きるので、描き直しは次のフレームに回す
  bool _depthRebuildScheduled = false;

  void _onTabDepthChanged() {
    if (_depthRebuildScheduled) return;
    _depthRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _depthRebuildScheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Timer? _followCaptureTimer;

  /// 初めてタイムラインが表示されたあと、見た目の選択を出すまでの待ち
  Timer? _styleSheetTimer;

  @override
  void dispose() {
    _followCaptureTimer?.cancel();
    _styleSheetTimer?.cancel();
    super.dispose();
  }

  /// タイムラインに投稿が並んだのを見てもらってから、見た目の選択を出す。
  /// 別のタブにいるときは出さず、タイムラインに来たときにもう一度試す
  void _maybeShowTimelineStyle() {
    if (!OnboardingService.instance.shouldShow(OnboardingStep.timelineStyle)) {
      return;
    }
    if (_currentIndex != 1 || _styleSheetTimer != null) return;
    if (ref.read(feedProvider).posts.isEmpty) return;
    _styleSheetTimer = Timer(const Duration(milliseconds: 2500), () {
      _styleSheetTimer = null;
      if (!mounted || _currentIndex != 1) return;
      if (!OnboardingService.instance
          .shouldShow(OnboardingStep.timelineStyle)) {
        return;
      }
      OnboardingService.instance.markSeen(OnboardingStep.timelineStyle);
      showTimelineStyleSheet(context);
    });
  }

  @override
  void initState() {
    super.initState();
    // 初期タブが通知タブ (index 2) だった場合のみ active=true
    if (_currentIndex == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(notificationTabActiveProvider.notifier).state = true;
      });
    }
    _scheduleFollowCapture();
  }

  /// 期日が来ているフォロー/フォロワー取得と、途中のつながり調査を
  /// 起動時に 1 回だけ走らせる。
  /// 起動直後はタイムライン取得と重なるので少し待ってから始める。
  /// 画面が消えたら止められるよう Timer で持つ（投げっぱなしにしない）。
  void _scheduleFollowCapture() {
    _followCaptureTimer = Timer(const Duration(seconds: 10), () async {
      if (!mounted) return;
      // 対象の SNS ごとに実行アカウントを選ぶので、ここでは絞らない
      final accounts = AccountStorageService.instance.accounts;
      if (accounts.isEmpty) return;
      try {
        await FollowCaptureJobService.instance.runDueWork(accounts: accounts);
      } catch (e) {
        debugPrint('[HomeScreen] 自動取得に失敗: $e');
      }
      // 取得が終わってから。どちらも走査用 WebView を使うので重ねられない
      if (!mounted) return;
      try {
        await BlockScanService.instance.resumeUnfinished(accounts: accounts);
      } catch (e) {
        debugPrint('[HomeScreen] 調査の自動再開に失敗: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final badge = ref.watch(notificationBadgeProvider);
    final unreadTotal = badge.total;
    ref.listen(feedProvider.select((s) => s.posts.isNotEmpty), (_, hasPosts) {
      if (hasPosts) _maybeShowTimelineStyle();
    });

    final wide = MediaQuery.sizeOf(context).width >= wideLayoutMinWidth;

    // 端末の戻るボタンでタブ内のNavigatorを戻す
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final navigator = _navigatorKeys[_currentIndex].currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        } else {
          // タブのルートにいる → アプリを閉じる
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: HomeRailScope(
          active: wide,
          rightInset: wide ? MediaQuery.paddingOf(context).right : 0,
          child: Row(
            children: [
              if (wide) _buildRail(unreadTotal),
              Expanded(
                // 向きを変えて列が出入りしても、タブの中身を作り直させない
                key: const ValueKey('home_content'),
                // 縦画面では下のバーが端末の操作バーを避けている。列にしたときは
                // 避けるものが無くなるので、ここで中身ごと内側に収める。
                // 横向きの操作バーは端末によって右にも下にも出る
                //
                // 左の切り欠き（カメラの穴）は列のほうで避けている。中身にも
                // 余白として残っていると、ヘッダーや区切り線がもう一度その分
                // 右へずれる
                child: MediaQuery.removePadding(
                  context: context,
                  removeLeft: wide,
                  child: SafeArea(
                  left: false,
                  top: false,
                  right: wide,
                  bottom: wide,
                  child: Stack(
                  children: [
                    IndexedStack(
                      index: _currentIndex,
                      children: [
                        _buildTabNavigator(0, const AccountsScreen()),
                        _buildTabNavigator(1, OmniFeedScreen(
                          onRegisterTimelineTap: (callback) => onTimelineTap = callback,
                        )),
                        _buildTabNavigator(2, const NotificationsScreen()),
                      ],
                    ),
                    // 下のバーの一部にすると、出るたびに本文が縮んで投稿ボタンが
                    // 上に動く。本文の上に重ねて、画面の並びは動かさない
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ComposeQueueBanner(),
                    ),
                  ],
                ),
                ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide ? null : _buildBottomBar(unreadTotal),
      ),
    );
  }

  /// 各タブを独自のNavigatorで囲む
  Widget _buildTabNavigator(int index, Widget child) {
    return Navigator(
      key: _navigatorKeys[index],
      observers: [_depthObservers[index]],
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => child,
      ),
    );
  }

  void _onTabTap(int index) {
    if (index == _currentIndex) {
      // 同じタブを再タップ → ルートまで戻す
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);

      // タイムラインタブならトップへスクロール
      if (index == 1) {
        onTimelineTap?.call();
        // 「使い方の説明をもう一度見る」の後、タイムラインにいたまま押されたとき用
        _maybeShowTimelineStyle();
      }
    } else {
      // 切替元のタブをルートに戻す
      _navigatorKeys[_currentIndex].currentState?.popUntil((route) => route.isFirst);

      // 通知タブに入る/離れる時の active 状態更新
      // タブ active = true の間だけ各タイルが markSeen を実行できる
      // （IndexedStack でバックグラウンドでも layout されて ListView.builder の
      //   itemBuilder が呼ばれ勝手に既読化される問題を防ぐ）
      // 件数バッジは cache.seenAt を元に都度再計算されるため、タブ切替で
      // 全クリア（旧 markSeen()）はしない。クリアしても直後の再計算で
      // 件数が戻ってきてバッジが点滅する原因になっていた。
      if (index == 2 && _currentIndex != 2) {
        ref.read(notificationTabActiveProvider.notifier).state = true;
      } else if (_currentIndex == 2 && index != 2) {
        ref.read(notificationTabActiveProvider.notifier).state = false;
      }
      setState(() => _currentIndex = index);
      if (index == 1) {
        _maybeShowTimelineStyle();
      } else {
        // 出す前にタブを離れたら、次にタイムラインへ来たときに出し直す
        _styleSheetTimer?.cancel();
        _styleSheetTimer = null;
      }
    }
  }

  /// いまのタブの中で次の画面を開く
  void _pushInCurrentTab(WidgetBuilder builder) {
    _navigatorKeys[_currentIndex]
        .currentState
        ?.push(MaterialPageRoute(builder: builder));
  }

  Widget _railButton(IconData icon, String tooltip, WidgetBuilder builder) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: () => _pushInCurrentTab(builder),
      constraints: headerButtonConstraints,
      padding: EdgeInsets.zero,
    );
  }

  /// 横に広い画面で、ヘッダーと下のバーの代わりに左へ立てる列
  Widget _buildRail(int unreadTotal) {
    final atRoot = _depthObservers[_currentIndex].atRoot;
    final hasAccounts = ref.watch(accountProvider.select((a) => a.isNotEmpty));

    // 縦画面で各タブのヘッダーにあるボタン。奥の画面に進んだら出さない
    final actions = <Widget>[
      if (atRoot && _currentIndex == 0 && hasAccounts) ...[
        _railButton(Icons.groups_outlined, 'フォロー / フォロワー',
            (_) => const FollowCaptureScreen()),
        _railButton(Icons.person_search, 'ユーザー検索',
            (_) => const UserSearchScreen()),
      ],
      if (atRoot && _currentIndex == 1) ...[
        const FeedQuickButtons(axis: Axis.vertical),
        const OverlayLaunchButton(),
      ],
    ];

    return HomeRail(
      currentIndex: _currentIndex,
      onTabTap: _onTabTap,
      unreadTotal: unreadTotal,
      actions: actions,
      footer: [
        if (atRoot)
          _railButton(Icons.settings_outlined, '設定',
              (_) => const SettingsScreen()),
      ],
    );
  }

  Widget _buildBottomBar(int unreadTotal) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget buildTab(int index, IconData icon, IconData selectedIcon, {bool showBadge = false, int flex = 1}) {
      final isSelected = _currentIndex == index;
      Widget iconWidget = Icon(
        isSelected ? selectedIcon : icon,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: 24,
      );
      if (showBadge) {
        iconWidget = Stack(
          clipBehavior: Clip.none,
          children: [
            iconWidget,
            // アイコンの右肩に左端を合わせ、桁が増えたら右へ伸ばす
            Positioned(
              left: 13,
              top: -6,
              child: CountBadge(count: unreadTotal),
            ),
          ],
        );
      }

      return Expanded(
        flex: flex,
        child: InkWell(
          onTap: () => _onTabTap(index),
          child: SizedBox(
            height: 52,
            child: Center(child: iconWidget),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        color: colorScheme.surface,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            buildTab(0, Icons.people_outline, Icons.people),
            buildTab(1, Icons.home_outlined, Icons.home, flex: 2),
            buildTab(2, Icons.notifications_outlined, Icons.notifications, showBadge: true),
          ],
        ),
      ),
    );
  }
}
