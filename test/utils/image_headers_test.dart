import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/utils/image_headers.dart';

void main() {
  group('kUserAgent', () {
    test('is non-empty', () {
      expect(kUserAgent, isNotEmpty);
    });

    test('contains Mozilla (browser UA format)', () {
      expect(kUserAgent, contains('Mozilla'));
    });

    test('contains Android (mobile UA)', () {
      expect(kUserAgent, contains('Android'));
    });

    test('contains AppleWebKit', () {
      expect(kUserAgent, contains('AppleWebKit'));
    });

    test('contains Chrome', () {
      expect(kUserAgent, contains('Chrome'));
    });

    test('contains Mobile', () {
      expect(kUserAgent, contains('Mobile'));
    });
  });

  group('kImageHeaders', () {
    test('contains User-Agent key', () {
      expect(kImageHeaders.containsKey('User-Agent'), isTrue);
    });

    test('User-Agent value equals kUserAgent', () {
      expect(kImageHeaders['User-Agent'], equals(kUserAgent));
    });

    test('is non-empty map', () {
      expect(kImageHeaders, isNotEmpty);
    });

    test('is Map<String, String>', () {
      expect(kImageHeaders, isA<Map<String, String>>());
    });
  });
}
