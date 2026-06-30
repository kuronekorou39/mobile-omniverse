import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_omniverse/main.dart' as app;
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/services/x_bearer_token_service.dart';
import 'package:mobile_omniverse/services/x_query_id_service.dart';
import 'package:mobile_omniverse/services/x_features_service.dart';
import 'package:mobile_omniverse/services/debug_log_service.dart';
import 'package:mobile_omniverse/services/notification_cache_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App startup', () {
    testWidgets('app launches without crash', (tester) async {
      await AccountStorageService.instance.load();
      await XBearerTokenService.instance.init();
      await XQueryIdService.instance.init();
      await XFeaturesService.instance.init();
      await DebugLogService.instance.init();
      await NotificationCacheService.instance.loadSeenAt();
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      // App should display without crashing
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('Settings screen', () {
    testWidgets('settings screen opens and shows sections', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to settings (tap settings icon)
      final settingsButton = find.byIcon(Icons.settings_outlined);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton.first);
        await tester.pumpAndSettle();

        // Verify sections exist
        expect(find.text('外観'), findsOneWidget);
        expect(find.text('レイアウト'), findsOneWidget);
        expect(find.text('タイムライン'), findsOneWidget);
        expect(find.text('メディア'), findsOneWidget);
        expect(find.text('アプリ情報'), findsOneWidget);
        expect(find.text('デバッグ'), findsOneWidget);
      }
    });

    testWidgets('debug section expands and shows items', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final settingsButton = find.byIcon(Icons.settings_outlined);
      if (settingsButton.evaluate().isNotEmpty) {
        await tester.tap(settingsButton.first);
        await tester.pumpAndSettle();

        // Scroll to and tap debug section
        final debugTile = find.text('デバッグ');
        if (debugTile.evaluate().isNotEmpty) {
          await tester.ensureVisible(debugTile);
          await tester.tap(debugTile);
          await tester.pumpAndSettle();

          // Verify debug items
          expect(find.text('アクションログ'), findsOneWidget);
          expect(find.text('queryId 管理'), findsOneWidget);
          expect(find.text('features 管理'), findsOneWidget);
        }
      }
    });
  });

  group('Bottom navigation', () {
    testWidgets('can switch between tabs', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Find bottom navigation items
      final accountsTab = find.byIcon(Icons.people_outline);
      if (accountsTab.evaluate().isNotEmpty) {
        await tester.tap(accountsTab.first);
        await tester.pumpAndSettle();
      }

      final notificationsTab = find.byIcon(Icons.notifications_outlined);
      if (notificationsTab.evaluate().isNotEmpty) {
        await tester.tap(notificationsTab.first);
        await tester.pumpAndSettle();
      }
    });
  });
}
