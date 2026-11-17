import 'package:flutter/material.dart';

/// 一覧を下へ送るとヘッダーを上へ隠し、上へ戻すと出す画面の枠。
/// タイムラインと同じく、ヘッダーは指の動きにそのままついて動く。
///
/// [Scaffold] の appBar と body をそのまま渡せば置き換えられる。
/// ヘッダーと一覧を 1 本のスクロールとしてつなぐので、中の縦の一覧は
/// 自前の ScrollController を持たせないこと（持つと、ヘッダーが動かない）
class HidingHeaderScaffold extends StatelessWidget {
  const HidingHeaderScaffold({
    super.key,
    required this.appBar,
    required this.body,
  });

  final PreferredSizeWidget appBar;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ステータスバーの帯は残す。ヘッダーはその裏へ隠れる
          SizedBox(height: MediaQuery.paddingOf(context).top),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: NestedScrollView(
                floatHeaderSlivers: true,
                headerSliverBuilder: (context, _) => [
                  SliverPersistentHeader(
                    floating: true,
                    delegate: _HeaderDelegate(appBar),
                  ),
                ],
                body: body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate(this.appBar);

  final PreferredSizeWidget appBar;

  @override
  double get maxExtent => appBar.preferredSize.height;

  @override
  double get minExtent => 0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    // 隠れるときは下端を残して上へ送る（中身は縮めない）
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.bottomCenter,
        minHeight: maxExtent,
        maxHeight: maxExtent,
        child: appBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_HeaderDelegate old) => old.appBar != appBar;
}
