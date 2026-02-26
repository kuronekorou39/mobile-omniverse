import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/models/activity_log.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/providers/activity_log_provider.dart';
import 'package:mobile_omniverse/screens/activity_log_screen.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Widget buildActivityLogScreen({List<ActivityLog>? logs}) {
    final notifier = ActivityLogNotifier();
    if (logs != null) {
      for (final log in logs) {
        notifier.add(log);
      }
    }

    return ProviderScope(
      overrides: [
        activityLogProvider.overrideWith((ref) => notifier),
      ],
      child: const MaterialApp(
        home: ActivityLogScreen(),
      ),
    );
  }

  testWidgets('renders title "Activity Log"', (tester) async {
    await tester.pumpWidget(buildActivityLogScreen());
    await tester.pumpAndSettle();

    expect(find.text('Activity Log'), findsOneWidget);
  });

  testWidgets('shows tab bar with two tabs', (tester) async {
    await tester.pumpWidget(buildActivityLogScreen());
    await tester.pumpAndSettle();

    // Tabs should contain "操作" and "TL取得"
    expect(find.textContaining('操作'), findsOneWidget);
    expect(find.textContaining('TL取得'), findsOneWidget);
  });

  testWidgets('shows empty state message when no logs', (tester) async {
    await tester.pumpWidget(buildActivityLogScreen());
    await tester.pumpAndSettle();

    expect(find.text('ログがありません'), findsOneWidget);
  });

  testWidgets('shows "全アカウント" filter chip', (tester) async {
    await tester.pumpWidget(buildActivityLogScreen());
    await tester.pumpAndSettle();

    expect(find.text('全アカウント'), findsOneWidget);
  });

  testWidgets('shows logs when provided', (tester) async {
    final logs = [
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.like,
        platform: SnsService.x,
        accountHandle: '@testuser',
        success: true,
        statusCode: 200,
        targetId: 'tweet_123',
        targetSummary: 'Hello world',
      ),
    ];

    await tester.pumpWidget(buildActivityLogScreen(logs: logs));
    await tester.pumpAndSettle();

    // Should show "操作 (1)" in the tab
    expect(find.textContaining('操作 (1)'), findsOneWidget);
    // Action label
    expect(find.text('いいね'), findsOneWidget);
  });

  testWidgets('shows fetch logs in TL取得 tab', (tester) async {
    final logs = [
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.timelineFetch,
        platform: SnsService.bluesky,
        accountHandle: '@bsky.test',
        success: true,
        statusCode: 200,
      ),
    ];

    await tester.pumpWidget(buildActivityLogScreen(logs: logs));
    await tester.pumpAndSettle();

    // Tab should show "TL取得 (1)"
    expect(find.textContaining('TL取得 (1)'), findsOneWidget);

    // Tap on the TL取得 tab
    await tester.tap(find.textContaining('TL取得 (1)'));
    await tester.pumpAndSettle();

    // Should show the fetch log
    expect(find.text('TL取得'), findsAtLeastNWidgets(1));
  });

  testWidgets('delete button is present', (tester) async {
    await tester.pumpWidget(buildActivityLogScreen());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('filter chip for account is shown when logs have accounts',
      (tester) async {
    final logs = [
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.like,
        platform: SnsService.x,
        accountHandle: '@alice',
        success: true,
      ),
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.repost,
        platform: SnsService.bluesky,
        accountHandle: '@bob',
        success: true,
      ),
    ];

    await tester.pumpWidget(buildActivityLogScreen(logs: logs));
    await tester.pumpAndSettle();

    expect(find.text('全アカウント'), findsOneWidget);
    expect(find.text('@alice'), findsAtLeastNWidgets(1));
    expect(find.text('@bob'), findsAtLeastNWidgets(1));
  });

  testWidgets('tapping account filter chip filters logs', (tester) async {
    final logs = [
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.like,
        platform: SnsService.x,
        accountHandle: '@alice',
        success: true,
        targetId: 'tweet_1',
        targetSummary: 'Alice liked',
      ),
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.repost,
        platform: SnsService.bluesky,
        accountHandle: '@bob',
        success: true,
        targetId: 'post_1',
        targetSummary: 'Bob reposted',
      ),
    ];

    await tester.pumpWidget(buildActivityLogScreen(logs: logs));
    await tester.pumpAndSettle();

    // Tab should show "操作 (2)" initially
    expect(find.textContaining('操作 (2)'), findsOneWidget);

    // Tap on @alice filter chip
    await tester.tap(find.text('@alice'));
    await tester.pumpAndSettle();

    // Now only 1 log for @alice
    expect(find.textContaining('操作 (1)'), findsOneWidget);
  });

  testWidgets('tapping clear button clears all logs', (tester) async {
    final logs = [
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.like,
        platform: SnsService.x,
        accountHandle: '@testuser',
        success: true,
      ),
    ];

    await tester.pumpWidget(buildActivityLogScreen(logs: logs));
    await tester.pumpAndSettle();

    expect(find.textContaining('操作 (1)'), findsOneWidget);

    // Tap the clear button
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // Logs should be cleared
    expect(find.textContaining('操作 (0)'), findsOneWidget);
    expect(find.text('ログがありません'), findsOneWidget);
  });

  testWidgets('TL取得 tab shows fetch log details with account info',
      (tester) async {
    final logs = [
      ActivityLog(
        timestamp: DateTime(2024, 3, 15, 10, 30, 45),
        action: ActivityAction.timelineFetch,
        platform: SnsService.x,
        accountHandle: '@xuser',
        success: true,
        statusCode: 200,
      ),
      ActivityLog(
        timestamp: DateTime(2024, 3, 15, 10, 30, 45),
        action: ActivityAction.timelineFetch,
        platform: SnsService.bluesky,
        accountHandle: '@bskyuser',
        success: false,
        errorMessage: 'Network timeout',
      ),
    ];

    await tester.pumpWidget(buildActivityLogScreen(logs: logs));
    await tester.pumpAndSettle();

    // Switch to TL取得 tab
    await tester.tap(find.textContaining('TL取得 (2)'));
    await tester.pumpAndSettle();

    // Should show the "最終取得" section
    expect(find.text('最終取得'), findsOneWidget);
    expect(find.text('@xuser'), findsAtLeastNWidgets(1));
    expect(find.text('@bskyuser'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows ChoiceChip widget for filter', (tester) async {
    await tester.pumpWidget(buildActivityLogScreen());
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsAtLeastNWidgets(1));
  });

  testWidgets('log with status code shows status in parentheses',
      (tester) async {
    final logs = [
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.like,
        platform: SnsService.x,
        accountHandle: '@testuser',
        success: true,
        statusCode: 200,
        targetId: 'tweet_123',
        targetSummary: 'Test post summary',
      ),
    ];

    await tester.pumpWidget(buildActivityLogScreen(logs: logs));
    await tester.pumpAndSettle();

    expect(find.text('(200)'), findsOneWidget);
  });

  testWidgets('log tile is expandable and shows details', (tester) async {
    final logs = [
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.like,
        platform: SnsService.x,
        accountHandle: '@testuser',
        success: true,
        targetId: 'tweet_abc',
        targetSummary: 'This is the target post',
      ),
    ];

    await tester.pumpWidget(buildActivityLogScreen(logs: logs));
    await tester.pumpAndSettle();

    // ExpansionTile should exist
    expect(find.byType(ExpansionTile), findsOneWidget);

    // Tap to expand
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    // Should show details
    expect(find.text('Target'), findsOneWidget);
    expect(find.text('tweet_abc'), findsOneWidget);
    expect(find.text('Post'), findsOneWidget);
    expect(find.text('This is the target post'), findsOneWidget);
  });

  testWidgets('log with error shows error detail in expanded tile',
      (tester) async {
    final logs = [
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.repost,
        platform: SnsService.bluesky,
        accountHandle: '@bsky',
        success: false,
        errorMessage: 'Connection refused',
      ),
    ];

    await tester.pumpWidget(buildActivityLogScreen(logs: logs));
    await tester.pumpAndSettle();

    // Tap to expand
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Connection refused'), findsOneWidget);
  });

  testWidgets('log with responseSnippet shows response detail',
      (tester) async {
    final logs = [
      ActivityLog(
        timestamp: DateTime.now(),
        action: ActivityAction.like,
        platform: SnsService.x,
        accountHandle: '@xuser',
        success: true,
        responseSnippet: '{"data":{"favorite_tweet":{"id":"123"}}}',
      ),
    ];

    await tester.pumpWidget(buildActivityLogScreen(logs: logs));
    await tester.pumpAndSettle();

    // Tap to expand
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(find.text('Response'), findsOneWidget);
  });
}
