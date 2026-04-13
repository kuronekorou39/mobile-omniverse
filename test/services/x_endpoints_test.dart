import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/x_endpoints.dart';

void main() {
  group('XEndpoints', () {
    test('badgeCount starts with https://x.com/', () {
      expect(XEndpoints.badgeCount, startsWith('https://x.com/'));
    });

    test('badgeCount is non-empty', () {
      expect(XEndpoints.badgeCount, isNotEmpty);
    });

    test('badgeCount contains badge_count path', () {
      expect(XEndpoints.badgeCount, contains('badge_count'));
    });

    test('notificationsAll starts with /i/api/', () {
      expect(XEndpoints.notificationsAll, startsWith('/i/api/'));
    });

    test('notificationsAll is non-empty', () {
      expect(XEndpoints.notificationsAll, isNotEmpty);
    });

    test('notificationsAll contains notifications path', () {
      expect(XEndpoints.notificationsAll, contains('notifications'));
    });

    test('graphqlBase starts with https://x.com/i/api/graphql', () {
      expect(XEndpoints.graphqlBase, startsWith('https://x.com/i/api/graphql'));
    });

    test('graphqlBase is non-empty', () {
      expect(XEndpoints.graphqlBase, isNotEmpty);
    });

    test('home equals https://x.com/home', () {
      expect(XEndpoints.home, equals('https://x.com/home'));
    });

    test('home is non-empty', () {
      expect(XEndpoints.home, isNotEmpty);
    });

    test('all endpoints are non-empty strings', () {
      final endpoints = [
        XEndpoints.badgeCount,
        XEndpoints.notificationsAll,
        XEndpoints.graphqlBase,
        XEndpoints.home,
      ];
      for (final ep in endpoints) {
        expect(ep, isA<String>());
        expect(ep, isNotEmpty);
      }
    });
  });
}
