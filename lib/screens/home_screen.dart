import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notification_badge_provider.dart';
import 'accounts_screen.dart';
import 'notifications_screen.dart';
import 'omni_feed_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 1; // デフォルト: タイムライン

  /// タイムラインタブを再タップ時にトップへスクロールするためのコールバック
  VoidCallback? onTimelineTap;

  @override
  Widget build(BuildContext context) {
    final hasUnread = ref.watch(notificationBadgeProvider);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const AccountsScreen(),
          OmniFeedScreen(
            onRegisterTimelineTap: (callback) => onTimelineTap = callback,
          ),
          const NotificationsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (index == 1 && _currentIndex == 1) {
            // タイムラインタブを再タップ → トップにスクロール
            onTimelineTap?.call();
          } else if (index == 2 && _currentIndex != 2) {
            // 通知タブに切替 → 既読マーク
            ref.read(notificationBadgeProvider.notifier).markSeen();
          }
          setState(() => _currentIndex = index);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'アカウント',
          ),
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'タイムライン',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: hasUnread,
              smallSize: 8,
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: hasUnread,
              smallSize: 8,
              child: const Icon(Icons.notifications),
            ),
            label: '通知',
          ),
        ],
      ),
    );
  }
}
