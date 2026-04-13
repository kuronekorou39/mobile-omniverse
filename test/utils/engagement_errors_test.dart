import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/utils/engagement_errors.dart';

void main() {
  group('engagementErrorMessage', () {
    test('known status code returns friendly message', () {
      expect(engagementErrorMessage('いいね', 142), contains('非公開アカウント'));
      expect(engagementErrorMessage('リポスト', 328), contains('非公開アカウント'));
      expect(engagementErrorMessage('リポスト', 429), contains('レート制限'));
    });

    test('unknown status code returns generic message with code', () {
      final msg = engagementErrorMessage('いいね', 999);
      expect(msg, contains('999'));
      expect(msg, contains('いいね'));
    });

    test('null status code returns generic message', () {
      final msg = engagementErrorMessage('いいね', null);
      expect(msg, contains('いいね'));
    });
  });
}
