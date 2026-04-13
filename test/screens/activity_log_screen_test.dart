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

  testWidgets('renders title "アクションログ"', (tester) async {
    await tester.pumpWidget(buildActivityLogScreen());
    await tester.pumpAndSettle();

    expect(find.text('アクションログ'), findsOneWidget);
  });

  testWidgets('shows empty state message when no logs', (tester) async {
    await tester.pumpWidget(buildActivityLogScreen());
    await tester.pumpAndSettle();

    expect(find.text('ログがありません'), findsOneWidget);
  });

  testWidgets('shows filter_list icon button', (tester) async {
    await tester.pumpWidget(buildActivityLogScreen());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.filter_list), findsOneWidget);
  });

  testWidgets('shows person_outline icon button', (tester) async {
    await tester.pumpWidget(buildActivityLogScreen());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person_outline), findsOneWidget);
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

    // Action label
    expect(find.text('いいね'), findsOneWidget);
  });

  testWidgets('shows fetch logs', (tester) async {
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

    // Should show the fetch log
    expect(find.text('TL取得'), findsAtLeastNWidgets(1));
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

  testWidgets('shows error message for failed logs', (tester) async {
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

    expect(find.text('Connection refused'), findsOneWidget);
  });

  testWidgets('tapping log entry with details shows bottom sheet',
      (tester) async {
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

    // Tap on the log entry (InkWell)
    await tester.tap(find.text('いいね'));
    await tester.pumpAndSettle();

    // Bottom sheet should show details
    expect(find.text('Target'), findsOneWidget);
    expect(find.text('tweet_abc'), findsOneWidget);
    expect(find.text('Post'), findsOneWidget);
    expect(find.text('This is the target post'), findsOneWidget);
  });

  testWidgets('tapping log with error shows error detail in bottom sheet',
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

    // Tap the log entry
    await tester.tap(find.text('リポスト'));
    await tester.pumpAndSettle();

    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Connection refused'), findsAtLeastNWidgets(1));
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

    // Tap the log entry
    await tester.tap(find.text('いいね'));
    await tester.pumpAndSettle();

    expect(find.text('Response'), findsOneWidget);
  });

  testWidgets('shows multiple logs', (tester) async {
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

    expect(find.text('いいね'), findsOneWidget);
    expect(find.text('リポスト'), findsOneWidget);
  });

  testWidgets('account filter shows account handles in popup menu',
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

    // Tap account filter button
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('全アカウント'), findsOneWidget);
    expect(find.text('@alice'), findsAtLeastNWidgets(1));
    expect(find.text('@bob'), findsAtLeastNWidgets(1));
  });
}
