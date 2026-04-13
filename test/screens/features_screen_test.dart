import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/screens/features_screen.dart';
import 'package:mobile_omniverse/services/x_features_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await XFeaturesService.instance.clearCache();
    await XFeaturesService.instance.init();
  });

  tearDown(() async {
    await XFeaturesService.instance.clearCache();
  });

  Future<void> pumpFeaturesScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FeaturesScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('FeaturesScreen', () {
    testWidgets('renders with correct title', (tester) async {
      await pumpFeaturesScreen(tester);
      expect(find.text('features 管理'), findsOneWidget);
    });

    testWidgets('shows HomeLatestTimeline operation', (tester) async {
      await pumpFeaturesScreen(tester);
      expect(find.text('HomeLatestTimeline'), findsOneWidget);
    });

    testWidgets('shows TweetDetail operation', (tester) async {
      await pumpFeaturesScreen(tester);
      expect(find.text('TweetDetail'), findsOneWidget);
    });

    testWidgets('shows UserTweets operation', (tester) async {
      await pumpFeaturesScreen(tester);
      expect(find.text('UserTweets'), findsOneWidget);
    });

    testWidgets('shows UserMedia operation', (tester) async {
      await pumpFeaturesScreen(tester);
      expect(find.text('UserMedia'), findsOneWidget);
    });

    testWidgets('shows NotificationsTimeline operation', (tester) async {
      await pumpFeaturesScreen(tester);
      expect(find.text('NotificationsTimeline'), findsOneWidget);
    });

    testWidgets('shows UserByScreenName operation', (tester) async {
      await pumpFeaturesScreen(tester);
      expect(find.text('UserByScreenName'), findsOneWidget);
    });

    testWidgets('shows CreateTweet operation', (tester) async {
      await pumpFeaturesScreen(tester);
      expect(find.text('CreateTweet'), findsOneWidget);
    });

    testWidgets('shows hardcoded label when no cache exists', (tester) async {
      await pumpFeaturesScreen(tester);
      // All operations should show hardcoded label since cache is empty
      final hardcodedFinder = find.textContaining('ハードコード定義');
      expect(hardcodedFinder, findsWidgets);
    });

    testWidgets('shows all 7 operations', (tester) async {
      await pumpFeaturesScreen(tester);
      final ops = [
        'HomeLatestTimeline', 'TweetDetail', 'UserTweets', 'UserMedia',
        'NotificationsTimeline', 'UserByScreenName', 'CreateTweet',
      ];
      for (final op in ops) {
        expect(find.text(op), findsOneWidget, reason: '$op should be shown');
      }
    });

    testWidgets('shows WebView label when cache exists', (tester) async {
      await XFeaturesService.instance.updateFeatures(
        'HomeLatestTimeline',
        {'test_key': true},
      );
      await pumpFeaturesScreen(tester);
      expect(find.textContaining('WebViewから取得'), findsWidgets);
    });

    testWidgets('shows code icon for hardcoded operations', (tester) async {
      await pumpFeaturesScreen(tester);
      // All operations are hardcoded (no cache), so should show code icons
      expect(find.byIcon(Icons.code), findsWidgets);
    });
  });
}
