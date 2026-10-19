import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/onboarding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final service = OnboardingService.instance;

  group('OnboardingService', () {
    test('新しく入れた人には全部の説明を出す', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init(hasAccounts: false);
      for (final step in OnboardingStep.values) {
        expect(service.shouldShow(step), isTrue, reason: step.name);
      }
    });

    test('アップデートで入ってきた人（アカウントあり）には出さない', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init(hasAccounts: true);
      for (final step in OnboardingStep.values) {
        expect(service.shouldShow(step), isFalse, reason: step.name);
      }
    });

    test('見たものは二度と出さない', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init(hasAccounts: false);
      await service.markSeen(OnboardingStep.compose);
      expect(service.shouldShow(OnboardingStep.compose), isFalse);
      expect(service.shouldShow(OnboardingStep.welcome), isTrue);
    });

    test('初回判定は 1 回だけ。あとでアカウントが増えても見ていない説明は残る', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init(hasAccounts: false);
      await service.init(hasAccounts: true);
      expect(service.shouldShow(OnboardingStep.timelineStyle), isTrue);
    });

    test('もう一度見るを押すと全部出し直す', () async {
      SharedPreferences.setMockInitialValues({});
      await service.init(hasAccounts: true);
      await service.resetAll();
      for (final step in OnboardingStep.values) {
        expect(service.shouldShow(step), isTrue, reason: step.name);
      }
    });
  });
}
