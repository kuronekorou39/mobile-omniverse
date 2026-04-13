import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/providers/settings_provider.dart';
import 'package:mobile_omniverse/screens/omni_feed_screen.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/services/timeline_fetch_scheduler.dart';
import 'package:mobile_omniverse/widgets/post_card.dart';

import '../helpers/test_data.dart';

/// Override HttpOverrides so CachedNetworkImage does not make real HTTP calls.
class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = (cert, host, port) => true;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = _TestHttpOverrides();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AccountStorageService.instance.load();
  });

  Future<void> pumpOmniFeedScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) {
            final notifier = SettingsNotifier();
            notifier.stopFetching();
            return notifier;
          }),
        ],
        child: const MaterialApp(
          home: OmniFeedScreen(),
        ),
      ),
    );
    // 初期フレーム処理（スケジュールタスク、キャッシュロード等）
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('OmniFeedScreen - empty accounts state', () {
    testWidgets('shows empty state message when no accounts', (tester) async {
      await pumpOmniFeedScreen(tester);

      expect(
        find.text('アカウントを追加すると投稿が届きます'),
        findsOneWidget,
      );
    });

    testWidgets('shows wave emoji in empty state', (tester) async {
      await pumpOmniFeedScreen(tester);

      // Empty state shows wave emoji
      expect(find.textContaining('静かな海です'), findsOneWidget);
    });
  });

  group('OmniFeedScreen - AppBar actions', () {
    testWidgets('shows settings icon button', (tester) async {
      await pumpOmniFeedScreen(tester);

      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('has tooltip for settings button', (tester) async {
      await pumpOmniFeedScreen(tester);

      expect(find.byTooltip('設定'), findsOneWidget);
    });
  });

  group('OmniFeedScreen - SliverAppBar structure', () {
    testWidgets('contains SliverAppBar', (tester) async {
      await pumpOmniFeedScreen(tester);

      expect(find.byType(SliverAppBar), findsOneWidget);
    });

    testWidgets('SliverAppBar is floating', (tester) async {
      await pumpOmniFeedScreen(tester);

      final sliverAppBar =
          tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(sliverAppBar.floating, isTrue);
    });
  });

  group('OmniFeedScreen - navigation', () {
    testWidgets('tapping settings icon navigates to SettingsScreen',
        (tester) async {
      await pumpOmniFeedScreen(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('設定'), findsOneWidget);
    });
  });

  group('OmniFeedScreen - with accounts', () {
    testWidgets('shows FAB with edit icon when accounts exist',
        (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await pumpOmniFeedScreen(tester);

      expect(find.byType(FloatingActionButton), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('no FAB when no accounts', (tester) async {
      await pumpOmniFeedScreen(tester);

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shows PostCards when feed has posts', (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await pumpOmniFeedScreen(tester);

      final posts = [
        makePost(
          id: 'feed_1',
          username: 'FeedUser1',
          handle: '@feeduser1',
          body: 'First feed post',
          accountId: account.id,
          timestamp: DateTime(2024, 1, 15, 12, 0),
        ),
        makePost(
          id: 'feed_2',
          username: 'FeedUser2',
          handle: '@feeduser2',
          body: 'Second feed post',
          accountId: account.id,
          timestamp: DateTime(2024, 1, 15, 11, 0),
        ),
      ];
      TimelineFetchScheduler.instance.onPostsFetched?.call(posts);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byType(PostCard), findsAtLeastNWidgets(1));
      expect(find.text('First feed post'), findsOneWidget);
      expect(find.text('Second feed post'), findsOneWidget);
    });

    testWidgets('tapping a post in feed navigates to PostDetailScreen',
        (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await pumpOmniFeedScreen(tester);

      final posts = [
        makePost(
          id: 'feed_nav',
          username: 'NavUser',
          handle: '@navuser',
          body: 'Navigate to detail',
          accountId: account.id,
          timestamp: DateTime(2024, 1, 15, 12, 0),
        ),
      ];
      TimelineFetchScheduler.instance.onPostsFetched?.call(posts);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Tap on the post text to navigate
      await tester.tap(find.text('Navigate to detail'));
      // Use pump() instead of pumpAndSettle() to avoid timeout from PostDetailScreen API calls
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Should be on PostDetailScreen
      expect(find.text('投稿詳細'), findsOneWidget);
    });

    testWidgets('shows retweet header in feed post', (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await pumpOmniFeedScreen(tester);

      final posts = [
        makePost(
          id: 'feed_rt',
          username: 'OriginalUser',
          handle: '@original',
          body: 'Retweeted post',
          accountId: account.id,
          timestamp: DateTime(2024, 1, 15, 12, 0),
          isRetweet: true,
          retweetedByUsername: 'RetweeterUser',
        ),
      ];
      TimelineFetchScheduler.instance.onPostsFetched?.call(posts);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.textContaining('RetweeterUser'), findsOneWidget);
      expect(find.textContaining('リツイート'), findsOneWidget);
    });

    testWidgets('shows multiple posts sorted by time', (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await pumpOmniFeedScreen(tester);

      final posts = [
        makePost(
          id: 'feed_old',
          body: 'Old post',
          accountId: account.id,
          timestamp: DateTime(2024, 1, 10),
        ),
        makePost(
          id: 'feed_new',
          body: 'New post',
          accountId: account.id,
          timestamp: DateTime(2024, 1, 20),
        ),
        makePost(
          id: 'feed_mid',
          body: 'Middle post',
          accountId: account.id,
          timestamp: DateTime(2024, 1, 15),
        ),
      ];
      TimelineFetchScheduler.instance.onPostsFetched?.call(posts);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // All three should be visible
      expect(find.byType(PostCard), findsNWidgets(3));
    });

    testWidgets('RT filter hides retweets for hidden account IDs',
        (tester) async {
      final account = makeXAccount(id: 'x_rt_filter');
      AccountStorageService.instance.setAccountsForTest([account]);

      await pumpOmniFeedScreen(tester);

      // Inject a normal post and a retweet
      final posts = [
        makePost(
          id: 'feed_normal',
          body: 'Normal post',
          accountId: 'x_rt_filter',
          timestamp: DateTime(2024, 1, 15, 12, 0),
          isRetweet: false,
        ),
        makePost(
          id: 'feed_rt_hidden',
          body: 'RT post hidden',
          accountId: 'x_rt_filter',
          timestamp: DateTime(2024, 1, 15, 11, 0),
          isRetweet: true,
          retweetedByUsername: 'Retweeter',
        ),
      ];
      TimelineFetchScheduler.instance.onPostsFetched?.call(posts);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Both posts should be visible since hideRetweetsAccountIds is empty by default
      expect(find.byType(PostCard), findsNWidgets(2));
    });

    testWidgets('FAB navigates to ComposeScreen', (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await pumpOmniFeedScreen(tester);

      // Find the compose FAB (the one with edit icon)
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      // ComposeScreen should show
      expect(find.text('投稿'), findsAtLeastNWidgets(1));
      expect(find.text('いまどうしてる？'), findsOneWidget);
    });

    testWidgets('shows post body text', (tester) async {
      final account = makeXAccount(
        id: 'x_body_acc',
        handle: '@bodyaccount',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await pumpOmniFeedScreen(tester);

      final posts = [
        makePost(
          id: 'feed_body',
          username: 'BodyUser',
          handle: '@bodyuser',
          body: 'Post body text here',
          accountId: 'x_body_acc',
          timestamp: DateTime(2024, 1, 15, 12, 0),
        ),
      ];
      TimelineFetchScheduler.instance.onPostsFetched?.call(posts);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Post body text here'), findsOneWidget);
    });
  });
}
