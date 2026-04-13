import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/main.dart';
import 'package:mobile_omniverse/services/timeline_fetch_scheduler.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TimelineFetchScheduler.instance.stop();
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OmniVerseApp()));
    // Allow async initialization to complete
    await tester.pump();

    // Stop scheduler timer before test ends (started by SettingsNotifier)
    TimelineFetchScheduler.instance.stop();

    // SplashScreen renders a logo image, not text
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
  });
}
