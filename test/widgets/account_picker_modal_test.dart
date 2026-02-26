import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/widgets/account_picker_modal.dart';

import '../helpers/test_data.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AccountStorageService.instance.setAccountsForTest([]);
  });

  group('showAccountPickerModal', () {
    testWidgets('returns null when no accounts exist', (tester) async {
      Account? result;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await showAccountPickerModal(
                  context,
                  service: SnsService.x,
                  actionLabel: 'いいね',
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('returns the only account when exactly one exists',
        (tester) async {
      final account = makeXAccount();
      AccountStorageService.instance.setAccountsForTest([account]);

      Account? result;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await showAccountPickerModal(
                  context,
                  service: SnsService.x,
                  actionLabel: 'いいね',
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.id, account.id);
    });

    testWidgets('shows modal with account list when multiple accounts exist',
        (tester) async {
      final account1 = makeXAccount(
        id: 'x_acc_1',
        displayName: 'Alice',
        handle: '@alice',
      );
      final account2 = makeXAccount(
        id: 'x_acc_2',
        displayName: 'Bob',
        handle: '@bob',
      );
      AccountStorageService.instance
          .setAccountsForTest([account1, account2]);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                await showAccountPickerModal(
                  context,
                  service: SnsService.x,
                  actionLabel: 'いいね',
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('いいね するアカウントを選択'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('tapping an account returns it and closes modal',
        (tester) async {
      final account1 = makeXAccount(
        id: 'x_acc_1',
        displayName: 'Alice',
        handle: '@alice',
      );
      final account2 = makeXAccount(
        id: 'x_acc_2',
        displayName: 'Bob',
        handle: '@bob',
      );
      AccountStorageService.instance
          .setAccountsForTest([account1, account2]);

      Account? result;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await showAccountPickerModal(
                  context,
                  service: SnsService.x,
                  actionLabel: 'いいね',
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.id, 'x_acc_2');
      expect(find.text('いいね するアカウントを選択'), findsNothing);
    });

    testWidgets('only shows accounts for the specified service',
        (tester) async {
      final xAccount = makeXAccount(
        id: 'x_acc_1',
        displayName: 'X User',
        handle: '@xuser',
      );
      final bskyAccount = makeBlueskyAccount(
        id: 'bsky_acc_1',
        displayName: 'Bluesky User',
        handle: '@bsky.user',
      );
      AccountStorageService.instance
          .setAccountsForTest([xAccount, bskyAccount]);

      Account? result;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                result = await showAccountPickerModal(
                  context,
                  service: SnsService.x,
                  actionLabel: 'いいね',
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Only one X account, should auto-return it without modal
      expect(result, isNotNull);
      expect(result!.id, 'x_acc_1');
    });

    testWidgets('shows avatar initials when avatarUrl is null',
        (tester) async {
      final account1 = makeXAccount(
        id: 'x_acc_1',
        displayName: 'Alice',
        handle: '@alice',
      );
      final account2 = makeXAccount(
        id: 'x_acc_2',
        displayName: 'Bob',
        handle: '@bob',
      );
      AccountStorageService.instance
          .setAccountsForTest([account1, account2]);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () async {
                await showAccountPickerModal(
                  context,
                  service: SnsService.x,
                  actionLabel: 'いいね',
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });
}
