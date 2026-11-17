import 'package:flutter/material.dart';

/// 一覧を下へ送るとヘッダーを上へ隠し、上へ戻すと出す画面の枠。
/// タイムラインと同じ動き。目線が下に行っている間は、一覧に高さを譲る。
///
/// [Scaffold] の appBar と body をそのまま渡せば置き換えられる。
/// 中の一覧が縦に動いたかどうかだけを見るので、タブで横に送る画面でも使える
class HidingHeaderScaffold extends StatefulWidget {
  const HidingHeaderScaffold({
    super.key,
    required this.appBar,
    required this.body,
  });

  final PreferredSizeWidget appBar;
  final Widget body;

  @override
  State<HidingHeaderScaffold> createState() => _HidingHeaderScaffoldState();
}

class _HidingHeaderScaffoldState extends State<HidingHeaderScaffold>
    with SingleTickerProviderStateMixin {
  /// 1 = 出ている、0 = 隠れている
  late final _shown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );

  /// 指先の小さな揺れで出し入れしないための遊び
  static const _threshold = 8.0;

  /// 同じ向きに動いた量の合計
  double _travel = 0;

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollUpdateNotification n) {
    final m = n.metrics;
    if (m.axis != Axis.vertical) return false;
    final delta = n.scrollDelta ?? 0;
    if (delta == 0) return false;

    // 先頭まで戻ったら必ず出す
    if (m.pixels <= m.minScrollExtent) {
      _travel = 0;
      _show(true);
      return false;
    }
    // 末尾で跳ね返る動きは、上へ戻す操作として数えない
    if (m.pixels >= m.maxScrollExtent) return false;

    if ((delta > 0) != (_travel > 0)) _travel = 0;
    _travel += delta;
    if (_travel > _threshold) {
      _show(false);
    } else if (_travel < -_threshold) {
      _show(true);
    }
    return false;
  }

  void _show(bool show) {
    if (show) {
      if (_shown.status != AnimationStatus.forward && _shown.value < 1) {
        _shown.forward();
      }
    } else {
      if (_shown.status != AnimationStatus.reverse && _shown.value > 0) {
        _shown.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ステータスバーの帯は残す。ヘッダーはその裏へ隠れる
          SizedBox(height: MediaQuery.paddingOf(context).top),
          ClipRect(
            child: SizeTransition(
              sizeFactor: _shown,
              alignment: Alignment.bottomLeft,
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: SizedBox(
                  height: widget.appBar.preferredSize.height,
                  child: widget.appBar,
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: _onScroll,
                child: widget.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
