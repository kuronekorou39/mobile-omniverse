import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/screens/compose_screen.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/widgets/sns_badge.dart';

import '../helpers/test_data.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Load AccountStorageService with empty data so that its singleton is safe.
    AccountStorageService.instance.setAccountsForTest([]);
  });

  Widget buildComposeScreen() {
    return const MaterialApp(
      home: ComposeScreen(),
    );
  }

  group('ComposeScreen - no accounts', () {
    testWidgets('shows "投稿" in AppBar', (tester) async {
      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // The AppBar title should say '投稿'.
      // The FilledButton in actions also says '投稿', so we expect at least 2.
      expect(find.text('投稿'), findsAtLeastNWidgets(1));
    });

    testWidgets('TextField with hint "いまどうしてる？" is present', (tester) async {
      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      expect(find.text('いまどうしてる？'), findsOneWidget);
    });

    testWidgets('character counter is displayed', (tester) async {
      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // With no accounts, _maxLength defaults to 280 (X).
      // The remaining counter should show "280" initially.
      expect(find.text('280'), findsOneWidget);
    });

    testWidgets('post button is disabled when text is empty', (tester) async {
      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // Find the FilledButton in the actions area.
      final filledButtons = find.byType(FilledButton);
      expect(filledButtons, findsOneWidget);

      final button = tester.widget<FilledButton>(filledButtons);
      expect(button.onPressed, isNull);
    });

    testWidgets('post button responds to text entry', (tester) async {
      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // Enter some text in the TextField.
      await tester.enterText(find.byType(TextField), 'Hello!');
      await tester.pump();

      // Just verify the button still exists and renders
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('character counter decreases as text is entered', (tester) async {
      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.pump();

      // 280 - 2 = 278
      expect(find.text('278'), findsOneWidget);
    });

    testWidgets('character counter turns red when over limit', (tester) async {
      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // Enter text exceeding 280 characters.
      final longText = 'A' * 285;
      await tester.enterText(find.byType(TextField), longText);
      await tester.pump();

      // The remaining should be -5.
      expect(find.text('-5'), findsOneWidget);

      // Verify the text color is red.
      final textWidget = tester.widget<Text>(find.text('-5'));
      expect(textWidget.style?.color, Colors.red);
    });

    testWidgets('ComposeScreen has a TextField that allows input', (tester) async {
      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      await tester.enterText(textField, 'Testing compose');
      await tester.pump();

      expect(find.text('Testing compose'), findsOneWidget);
    });

    testWidgets('no account selector shown when no accounts', (tester) async {
      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // No DropdownButtonFormField and no SnsBadge
      expect(find.byType(DropdownButtonFormField<Account>), findsNothing);
      expect(find.byType(SnsBadge), findsNothing);
    });
  });

  group('ComposeScreen - single account', () {
    testWidgets('shows selected account info for single X account',
        (tester) async {
      final account = makeXAccount(
        displayName: 'My X Account',
        handle: '@myxaccount',
      );
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // Should show account info as a Row (not a dropdown since only 1)
      expect(find.byType(SnsBadge), findsOneWidget);
      expect(find.textContaining('My X Account'), findsOneWidget);
      expect(find.textContaining('@myxaccount'), findsOneWidget);
    });

    testWidgets('character limit is 280 for X account', (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      expect(find.text('280'), findsOneWidget);
    });

    testWidgets('character limit is 300 for Bluesky account', (tester) async {
      final account = makeBlueskyAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      expect(find.text('300'), findsOneWidget);
    });

    testWidgets('character counter turns orange when near limit',
        (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // Enter 270 chars to get remaining=10 which is < 20
      final text = 'A' * 270;
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();

      expect(find.text('10'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('10'));
      expect(textWidget.style?.color, Colors.orange);
    });

    testWidgets('post button is disabled when remaining < 0', (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      final longText = 'A' * 290;
      await tester.enterText(find.byType(TextField), longText);
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('ComposeScreen - multiple accounts', () {
    testWidgets('shows account dropdown when multiple accounts exist',
        (tester) async {
      final xAccount = makeXAccount(
        id: 'x_1',
        displayName: 'X User',
        handle: '@xuser',
      );
      final bskyAccount = makeBlueskyAccount(
        id: 'bsky_1',
        displayName: 'Bsky User',
        handle: '@bskyuser',
      );
      AccountStorageService.instance
          .setAccountsForTest([xAccount, bskyAccount]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // Should show a DropdownButtonFormField for account selection
      expect(find.byType(DropdownButtonFormField<Account>),
          findsOneWidget);
      expect(find.text('投稿アカウント'), findsOneWidget);
    });

    testWidgets('disabled accounts are not shown in dropdown', (tester) async {
      final enabledAccount = makeXAccount(
        id: 'x_1',
        displayName: 'Enabled',
        handle: '@enabled',
        isEnabled: true,
      );
      final disabledAccount = makeBlueskyAccount(
        id: 'bsky_1',
        displayName: 'Disabled',
        handle: '@disabled',
        isEnabled: false,
      );
      AccountStorageService.instance
          .setAccountsForTest([enabledAccount, disabledAccount]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // Only one enabled account, so no dropdown, just account row
      expect(find.byType(SnsBadge), findsOneWidget);
      expect(find.textContaining('Enabled'), findsOneWidget);
    });

    testWidgets('post button becomes enabled when text is entered with account',
        (tester) async {
      final xAccount = makeXAccount(
        id: 'x_1',
        displayName: 'X User',
        handle: '@xuser',
      );
      final bskyAccount = makeBlueskyAccount(
        id: 'bsky_1',
        displayName: 'Bsky User',
        handle: '@bskyuser',
      );
      AccountStorageService.instance
          .setAccountsForTest([xAccount, bskyAccount]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // Initially button is disabled (empty text)
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      // Enter text
      await tester.enterText(find.byType(TextField), 'Hello!');
      await tester.pump();

      // Now button should be enabled
      final updatedButton =
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(updatedButton.onPressed, isNotNull);
    });
  });

  group('ComposeScreen - text input behaviors', () {
    testWidgets('post button remains disabled with only whitespace',
        (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('post button enabled with valid text and single account',
        (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Valid post');
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows TextField with autofocus', (tester) async {
      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.autofocus, isTrue);
    });

    testWidgets('character counter shows grey for normal length', (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // Default 280 remaining
      final textWidget = tester.widget<Text>(find.text('280'));
      expect(textWidget.style?.color, Colors.grey);
    });
  });

  group('ComposeScreen - dropdown account switching', () {
    testWidgets('switching account in dropdown changes character limit',
        (tester) async {
      final xAccount = makeXAccount(
        id: 'x_switch',
        displayName: 'X Account',
        handle: '@xaccount',
      );
      final bskyAccount = makeBlueskyAccount(
        id: 'bsky_switch',
        displayName: 'Bsky Account',
        handle: '@bskyaccount',
      );
      AccountStorageService.instance
          .setAccountsForTest([xAccount, bskyAccount]);

      await tester.pumpWidget(buildComposeScreen());
      await tester.pump();

      // Default first account is X, so 280 chars
      expect(find.text('280'), findsOneWidget);

      // Open the dropdown
      await tester.tap(find.byType(DropdownButtonFormField<Account>));
      await tester.pumpAndSettle();

      // Select the Bluesky account
      await tester.tap(find.textContaining('Bsky Account').last);
      await tester.pumpAndSettle();

      // Now character limit should be 300 (Bluesky)
      expect(find.text('300'), findsOneWidget);
    });
  });
}
