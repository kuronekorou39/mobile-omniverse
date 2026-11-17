import 'package:flutter/material.dart';

import 'count_badge.dart';

/// これ以上の幅があれば、ヘッダーと下のバーをやめて左の列にまとめる。
/// スマホの横向きとタブレットが当てはまる
const wideLayoutMinWidth = 600.0;

/// 横に広い画面で、読みもの（投稿・通知の並び）に使う幅の上限。
/// 画面いっぱいに伸ばすと 1 行が長くなりすぎて目で追いにくい
const readableContentMaxWidth = 680.0;

/// 読みものを画面の中央に置くための左右の余白。
///
/// [availableWidth] は左の列を除いた、中身に使える幅。この幅の中で中央に
/// 寄せると列のぶんだけ右へずれて見えるので、画面全体の中央に合わせる。
/// 列や端末の操作バーに当たるときは、幅のほうを狭めて左右対称を保つ。
///
/// [rightTaken] は、呼び出し側が中身の右隣に置いているものの幅。
EdgeInsets readableInsets(
  BuildContext context,
  double availableWidth, {
  double rightTaken = 0,
}) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  // 中身の右側を塞いでいる幅（端末の操作バーと、右隣に置いたもの）
  final right = HomeRailScope.rightInsetOf(context) + rightTaken;
  // 中身の左側を塞いでいる幅（左の列と、その外の切り欠き）
  final left = screenWidth - availableWidth - right;

  var margin = (screenWidth - readableContentMaxWidth) / 2;
  if (margin < left) margin = left;
  if (margin < right) margin = right;
  return EdgeInsets.only(left: margin - left, right: margin - right);
}

/// 奥の画面の本文を、横に広い画面では読みやすい幅に絞って画面の中央に置く。
///
/// 向きを変えても中身を作り直さないよう、絞らないときも同じ形の木にする
/// （作り直すと読み込み済みの一覧やスクロール位置が消える）。
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final active = HomeRailScope.isActive(context);
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: active
            ? readableInsets(context, constraints.maxWidth)
            : EdgeInsets.zero,
        child: child,
      ),
    );
  }
}

/// 横に広い画面では 2 列に分けて、縦にスクロールしなくても収まるようにする。
///
/// 縦画面では [single] の順で 1 列に積む。項目の順番は列に分けたときと
/// 縦に積んだときで変わるので、それぞれ渡してもらう。
class WideColumns extends StatelessWidget {
  const WideColumns({
    super.key,
    required this.single,
    required this.first,
    required this.second,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> single;
  final List<Widget> first;
  final List<Widget> second;
  final EdgeInsets padding;

  /// 2 列の間隔
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    if (!HomeRailScope.isActive(context)) {
      return ListView(padding: padding, children: single);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: padding.copyWith(right: _gap / 2),
            children: first,
          ),
        ),
        Expanded(
          child: ListView(
            padding: padding.copyWith(left: _gap / 2),
            children: second,
          ),
        ),
      ],
    );
  }
}

/// ホーム画面が左の列（[HomeRail]）を出しているかを、各タブの画面へ伝える。
///
/// 画面の幅だけで判断させると、ホームの外で単体で開かれたときに
/// ヘッダーも列も無い画面になる。列が実際に出ているときだけ
/// ヘッダーを外せるよう、出している側が知らせる。
class HomeRailScope extends InheritedWidget {
  const HomeRailScope({
    super.key,
    required this.active,
    required this.rightInset,
    required super.child,
  });

  final bool active;

  /// ホームが中身の右側で避けた幅（横向きのときの端末の操作バーなど）。
  /// 避けたあとの中身からは見えなくなるので、ここで伝える
  final double rightInset;

  static double rightInsetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeRailScope>()?.rightInset ??
      0;

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeRailScope>()?.active ??
      false;

  @override
  bool updateShouldNotify(HomeRailScope oldWidget) =>
      active != oldWidget.active || rightInset != oldWidget.rightInset;
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
