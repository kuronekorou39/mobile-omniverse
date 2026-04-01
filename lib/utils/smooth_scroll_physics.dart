import 'package:flutter/widgets.dart';

/// Twitter風の滑らかな慣性スクロール
/// デフォルトのClampingScrollPhysicsより減衰が緩やかで自然な感触
class SmoothScrollPhysics extends ScrollPhysics {
  const SmoothScrollPhysics({super.parent});

  @override
  SmoothScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SmoothScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // 速度がほぼゼロ → Simulationなし（アイドル状態に遷移 → タップが効く）
    if (velocity.abs() < toleranceFor(position).velocity) {
      return null;
    }

    // 境界外の場合はデフォルトのバウンスバック処理に委譲
    if (position.pixels < position.minScrollExtent ||
        position.pixels > position.maxScrollExtent) {
      return super.createBallisticSimulation(position, velocity);
    }

    // デフォルトの friction (0.015) より小さい値で減衰を緩やかに
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      friction: 0.008,
    );
  }

  // 端でのオーバースクロールは無効（Android標準）
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value < position.minScrollExtent) {
      return value - position.minScrollExtent;
    }
    if (value > position.maxScrollExtent) {
      return value - position.maxScrollExtent;
    }
    return 0.0;
  }
}
