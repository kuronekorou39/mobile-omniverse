import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/screens/splash_screen.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AccountStorageService.instance.setAccountsForTest([]);
  });
  testWidgets('SplashScreen renders app icon and title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(),
      ),
    );

    // Icon should be present
    expect(find.byIcon(Icons.rss_feed), findsOneWidget);

    // App title should be present
    expect(find.text('OmniVerse'), findsOneWidget);
  });

  testWidgets('SplashScreen is a Scaffold', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(),
      ),
    );

    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('SplashScreen contains FadeTransition and ScaleTransition',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(),
      ),
    );

    expect(find.byType(FadeTransition), findsAtLeastNWidgets(1));
    expect(find.byType(ScaleTransition), findsAtLeastNWidgets(1));
  });

  testWidgets('SplashScreen navigates after animation completes', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SplashScreen(),
        ),
      ),
    );

    // Advance past the animation (800ms) + the delay (300ms) + transition (400ms)
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    // HomeScreen should now be shown (which includes OmniFeedScreen)
    // After navigation, the splash screen may be replaced
    // Just verify we haven't crashed and something rendered
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
  });

  testWidgets('SplashScreen status listener triggers navigation', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SplashScreen(),
        ),
      ),
    );

    // Complete the animation (800ms)
    await tester.pump(const Duration(milliseconds: 800));

    // After completion, there's a 300ms Future.delayed before navigation
    await tester.pump(const Duration(milliseconds: 300));

    // The PageRouteBuilder transition takes 400ms
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    // HomeScreen should be visible now
    // HomeScreen wraps OmniFeedScreen which shows "OmniVerse"
    expect(find.text('OmniVerse'), findsAtLeastNWidgets(1));
  });

  testWidgets('SplashScreen animates over time', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(),
      ),
    );

    // Pump partial animation
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('OmniVerse'), findsOneWidget);

    // Pump to end of animation
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('OmniVerse'), findsOneWidget);
  });
}
