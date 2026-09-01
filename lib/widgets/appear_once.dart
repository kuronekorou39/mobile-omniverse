import 'package:flutter/material.dart';

/// 初めて画面に出るときだけ、すっと現れる。
///
/// 通知は上から差し込まれるので、何の演出もないと「いつの間にか増えている」
/// ようにしか見えない。かといって [AnimatedList] に置き換えると、差分の
/// 管理を呼び出し側が全部持つことになり、フィルタや複数アカウントの合流と
/// 相性が悪い。
///
/// そこで「新しく来たものだけ [enabled] を true にして包む」形にした。
/// スクロールで再構築されただけの行は演出しない ([enabled] が false)。
class AppearOnce extends StatefulWidget {
  const AppearOnce({
    super.key,
    required this.child,
    this.enabled = true,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;

  /// false なら何もせずそのまま出す
  final bool enabled;
  final Duration duration;

  @override
  State<AppearOnce> createState() => _AppearOnceState();
}

class _AppearOnceState extends State<AppearOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    // 演出しないときは最初から出来上がった状態にしておく
    value: widget.enabled ? 0 : 1,
  );

  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    // 終わったら組み直して、Opacity と Align を外す。放っておくと
    // 演出が済んだ行にも余計なレイヤーが残り続ける
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isCompleted) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      // 中身は毎フレーム作り直さない
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Align(
          heightFactor: _curve.value,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
    );
  }
}

/// 「どれが新しく来たか」を覚えておくための小物。
///
/// 最初の 1 回は演出しない。全部が新着なので、一斉に動くとかえって
/// 落ち着かないうえ、起動のたびにリストが波打つことになる。
class NewItemTracker {
  final _seen = <String>{};
  bool _primed = false;

  /// [id] が今回はじめて現れたか。初回の読み込みでは常に false を返す
  bool isNew(String id) => _primed && !_seen.contains(id);

  /// 描画したぶんを覚える。build のあとに呼ぶこと
  void remember(Iterable<String> ids) {
    _seen.addAll(ids);
    _primed = true;
  }

  void reset() {
    _seen.clear();
    _primed = false;
  }
}
