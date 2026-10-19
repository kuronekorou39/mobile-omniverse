import 'package:shared_preferences/shared_preferences.dart';

/// 初めて使う人向けの説明。それぞれ 1 回だけ出す
enum OnboardingStep {
  /// 初回起動（アカウント未登録）のようこそ + 追加ボタンの案内
  welcome,

  /// タイムラインが初めて表示されたときの見た目の選択
  timelineStyle,

  /// 投稿画面で、複数アカウントに同時投稿できることの案内
  compose,

  /// アカウント詳細でできることの紹介
  accountDetail,
}

/// 説明を「見たかどうか」を端末に保存する。
///
/// init 前（ウィジェットテストなど）は何も出さない。
class OnboardingService {
  OnboardingService._();
  static final instance = OnboardingService._();

  static const _initializedKey = 'onboarding_initialized';
  static String _seenKey(OnboardingStep step) => 'onboarding_seen_${step.name}';

  SharedPreferences? _prefs;

  /// [hasAccounts] はこの仕組みが入る前から使っている人の判定に使う。
  /// アカウントがある人は使い方を知っているので、全部見たことにする
  Future<void> init({required bool hasAccounts}) async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    if (prefs.getBool(_initializedKey) == true) return;
    if (hasAccounts) {
      for (final step in OnboardingStep.values) {
        await prefs.setBool(_seenKey(step), true);
      }
    }
    await prefs.setBool(_initializedKey, true);
  }

  bool shouldShow(OnboardingStep step) {
    final prefs = _prefs;
    if (prefs == null) return false;
    return prefs.getBool(_seenKey(step)) != true;
  }

  /// 出した時点で見たことにする。途中でアプリを閉じても何度も出さない
  Future<void> markSeen(OnboardingStep step) async {
    await _prefs?.setBool(_seenKey(step), true);
  }

  /// 設定の「使い方の説明をもう一度見る」用
  Future<void> resetAll() async {
    for (final step in OnboardingStep.values) {
      await _prefs?.remove(_seenKey(step));
    }
  }
}
