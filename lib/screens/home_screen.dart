import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notification_badge_provider.dart';
import '../services/account_storage_service.dart';
import 'accounts_screen.dart';
import 'notifications_screen.dart';
import 'omni_feed_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final hasUnread = ref.watch(notificationBadgeProvider).isNotEmpty;

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
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildTabNavigator(0, const AccountsScreen()),
            _buildTabNavigator(1, OmniFeedScreen(
              onRegisterTimelineTap: (callback) => onTimelineTap = callback,
            )),
            _buildTabNavigator(2, const NotificationsScreen()),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(hasUnread),
      ),
    );
  }

  /// 各タブを独自のNavigatorで囲む
  Widget _buildTabNavigator(int index, Widget child) {
    return Navigator(
      key: _navigatorKeys[index],
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
      }
    } else {
      // 切替元のタブをルートに戻す
      _navigatorKeys[_currentIndex].currentState?.popUntil((route) => route.isFirst);

      // 通知タブを離れる時に既読マーク
      if (_currentIndex == 2 && index != 2) {
        ref.read(notificationBadgeProvider.notifier).markSeen();
      }
      setState(() => _currentIndex = index);
    }
  }

  Widget _buildBottomBar(bool hasUnread) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget buildTab(int index, IconData icon, IconData selectedIcon, {bool showBadge = false, int flex = 1}) {
      final isSelected = _currentIndex == index;
      Widget iconWidget = Icon(
        isSelected ? selectedIcon : icon,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: 24,
      );
      if (showBadge) {
        iconWidget = Badge(
          isLabelVisible: hasUnread,
          smallSize: 8,
          child: iconWidget,
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
