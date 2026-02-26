import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/sns_service.dart';

void main() {
  group('SnsService', () {
    test('X の label', () {
      expect(SnsService.x.label, 'X');
    });

    test('X の homeUrl', () {
      expect(SnsService.x.homeUrl, 'https://x.com/home');
    });

    test('X の domain', () {
      expect(SnsService.x.domain, 'x.com');
    });

    test('Bluesky の label', () {
      expect(SnsService.bluesky.label, 'Bluesky');
    });

    test('Bluesky の homeUrl', () {
      expect(SnsService.bluesky.homeUrl, 'https://bsky.app/');
    });

    test('Bluesky の domain', () {
      expect(SnsService.bluesky.domain, 'bsky.app');
    });

    test('values は2つ', () {
      expect(SnsService.values.length, 2);
    });

    test('name プロパティ', () {
      expect(SnsService.x.name, 'x');
      expect(SnsService.bluesky.name, 'bluesky');
    });
  });
}
