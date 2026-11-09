import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/x_webview_action_service.dart';

void main() {
  group('XWebViewActionService.isLoginUrl', () {
    test('ログインへ飛ばされた URL を見分ける', () {
      expect(
          XWebViewActionService.isLoginUrl(
              'https://x.com/i/jf/onboarding/web?redirect_after_login=%2Fcompose%2Fpost&mode=login'),
          isTrue);
      expect(XWebViewActionService.isLoginUrl('https://x.com/i/flow/login'),
          isTrue);
      expect(XWebViewActionService.isLoginUrl('https://x.com/login?x=1'),
          isTrue);
    });

    test('投稿画面や通常のページは違う', () {
      expect(XWebViewActionService.isLoginUrl('https://x.com/compose/post'),
          isFalse);
      expect(
          XWebViewActionService.isLoginUrl(
              'https://x.com/intent/post?in_reply_to=1&text=login'),
          isFalse);
      expect(XWebViewActionService.isLoginUrl('https://x.com/home'), isFalse);
      expect(XWebViewActionService.isLoginUrl(''), isFalse);
    });
  });
}
