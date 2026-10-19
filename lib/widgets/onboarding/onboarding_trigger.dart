import 'package:flutter/material.dart';

import '../../services/onboarding_service.dart';

/// 画面を初めて開いたときに 1 回だけ [show] を呼ぶ。
///
/// 画面遷移のアニメーション中に出すと重なって見づらいので、少し待ってから出す。
class OnboardingTrigger extends StatefulWidget {
  const OnboardingTrigger({
    super.key,
    required this.step,
    required this.show,
    required this.child,
    this.when,
    this.delay = const Duration(milliseconds: 450),
  });

  final OnboardingStep step;
  final Future<void> Function(BuildContext context) show;
  final Widget child;

  /// 出す条件を足したいとき。false の間は出さず、見たことにもしない
  final bool Function()? when;
  final Duration delay;

  @override
  State<OnboardingTrigger> createState() => _OnboardingTriggerState();
}

class _OnboardingTriggerState extends State<OnboardingTrigger> {
  @override
  void initState() {
    super.initState();
    if (!OnboardingService.instance.shouldShow(widget.step)) return;
    Future.delayed(widget.delay, () {
      if (!mounted) return;
      if (!OnboardingService.instance.shouldShow(widget.step)) return;
      if (widget.when != null && !widget.when!()) return;
      OnboardingService.instance.markSeen(widget.step);
      widget.show(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
