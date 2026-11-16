import 'package:flutter/material.dart';

import 'count_badge.dart';

/// これ以上の幅があれば、ヘッダーと下のバーをやめて左の列にまとめる。
/// スマホの横向きとタブレットが当てはまる
const wideLayoutMinWidth = 600.0;

/// 横に広い画面で、読みもの（投稿・通知の並び）に使う幅の上限。
/// 画面いっぱいに伸ばすと 1 行が長くなりすぎて目で追いにくい
const readableContentMaxWidth = 680.0;

/// [availableWidth] の中で読みものを中央に寄せるための左右の余白
double readableSidePadding(double availableWidth) {
  final extra = availableWidth - readableContentMaxWidth;
  return extra > 0 ? extra / 2 : 0;
}

/// ホーム画面が左の列（[HomeRail]）を出しているかを、各タブの画面へ伝える。
///
/// 画面の幅だけで判断させると、ホームの外で単体で開かれたときに
/// ヘッダーも列も無い画面になる。列が実際に出ているときだけ
/// ヘッダーを外せるよう、出している側が知らせる。
class HomeRailScope extends InheritedWidget {
  const HomeRailScope({super.key, required this.active, required super.child});

  final bool active;

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeRailScope>()?.active ??
      false;

  @override
  bool updateShouldNotify(HomeRailScope oldWidget) => active != oldWidget.active;
}

/// 横に広い画面で左端に立てる列。
///
/// 縦画面では下のバーにあるタブと、ヘッダーにあるボタンを 1 列にまとめる。
class HomeRail extends StatelessWidget {
  const HomeRail({
    super.key,
    required this.currentIndex,
    required this.onTabTap,
    required this.unreadTotal,
    required this.actions,
    required this.footer,
  });

  final int currentIndex;
  final ValueChanged<int> onTabTap;
  final int unreadTotal;

  /// いまのタブのヘッダーにあたるボタン
  final List<Widget> actions;

  /// 列の一番下に固定するボタン
  final List<Widget> footer;

  static const _width = 64.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          right: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: _width,
          child: Column(
            children: [
              const SizedBox(height: 8),
              _tab(scheme, 0, Icons.people_outline, Icons.people, 'アカウント'),
              _tab(scheme, 1, Icons.home_outlined, Icons.home, 'タイムライン'),
              _tab(scheme, 2, Icons.notifications_outlined,
                  Icons.notifications, '通知',
                  badge: true),
              if (actions.isNotEmpty)
                Divider(
                  height: 17,
                  indent: 16,
                  endIndent: 16,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              // 低い画面で収まらないときは、この部分だけ送れるようにする
              Expanded(
                child: SingleChildScrollView(
                  child: Column(children: actions),
                ),
              ),
              ...footer,
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(
    ColorScheme scheme,
    int index,
    IconData icon,
    IconData selectedIcon,
    String tooltip, {
    bool badge = false,
  }) {
    final selected = currentIndex == index;
    Widget iconWidget = Icon(
      selected ? selectedIcon : icon,
      color: selected ? scheme.primary : scheme.onSurfaceVariant,
      size: 24,
    );
    if (badge) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            left: 13,
            top: -6,
            child: CountBadge(count: unreadTotal),
          ),
        ],
      );
    }
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onTabTap(index),
        customBorder: const StadiumBorder(),
        child: SizedBox(
          width: _width,
          height: 48,
          child: Center(
            // 選んでいるタブは面で持ち上げる
            child: Container(
              width: 48,
              height: 32,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(child: iconWidget),
            ),
          ),
        ),
      ),
    );
  }
}
