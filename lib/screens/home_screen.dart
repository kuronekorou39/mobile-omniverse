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
    final hasUnread = ref.watch(notificationBadgeProvider).isNotEmpty;

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
      bottomNavigationBar: _buildBottomBar(hasUnread),
    );
  }

  void _onTabTap(int index) {
    if (index == 1 && _currentIndex == 1) {
      onTimelineTap?.call();
    } else if (index == 2 && _currentIndex != 2) {
      // 通知画面のアカウント別ドットが見えるよう、少し遅延してから既読化
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) ref.read(notificationBadgeProvider.notifier).markSeen();
      });
    }
    setState(() => _currentIndex = index);
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
