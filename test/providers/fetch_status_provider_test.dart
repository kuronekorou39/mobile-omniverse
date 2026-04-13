import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/providers/fetch_status_provider.dart';

void main() {
  late FetchStatusNotifier notifier;

  setUp(() {
    notifier = FetchStatusNotifier();
  });

  group('FetchStatusNotifier', () {
    test('initial state is empty map', () {
      expect(notifier.state, isEmpty);
    });

    test('update with success sets health to good', () {
      notifier.update('acc_1', true);
      final status = notifier.state['acc_1']!;
      expect(status.health, AccountHealth.good);
      expect(status.consecutiveFailures, 0);
    });

    test('update with single failure sets health to warning', () {
      notifier.update('acc_1', false);
      final status = notifier.state['acc_1']!;
      expect(status.health, AccountHealth.warning);
      expect(status.consecutiveFailures, 1);
    });

    test('update with two consecutive failures sets health to error', () {
      notifier.update('acc_1', false);
      notifier.update('acc_1', false);
      final status = notifier.state['acc_1']!;
      expect(status.health, AccountHealth.error);
      expect(status.consecutiveFailures, 2);
    });

    test('update with three consecutive failures keeps health at error', () {
      notifier.update('acc_1', false);
      notifier.update('acc_1', false);
      notifier.update('acc_1', false);
      final status = notifier.state['acc_1']!;
      expect(status.health, AccountHealth.error);
      expect(status.consecutiveFailures, 3);
    });

    test('success after failure resets counter and sets good', () {
      notifier.update('acc_1', false);
      notifier.update('acc_1', false);
      expect(notifier.state['acc_1']!.health, AccountHealth.error);

      notifier.update('acc_1', true);
      final status = notifier.state['acc_1']!;
      expect(status.health, AccountHealth.good);
      expect(status.consecutiveFailures, 0);
    });

    test('setExpired sets error with 99 failures', () {
      notifier.setExpired('acc_1');
      final status = notifier.state['acc_1']!;
      expect(status.health, AccountHealth.error);
      expect(status.consecutiveFailures, 99);
    });

    test('setExpired overrides previous good state', () {
      notifier.update('acc_1', true);
      expect(notifier.state['acc_1']!.health, AccountHealth.good);

      notifier.setExpired('acc_1');
      expect(notifier.state['acc_1']!.health, AccountHealth.error);
      expect(notifier.state['acc_1']!.consecutiveFailures, 99);
    });

    test('multiple accounts are tracked independently', () {
      notifier.update('acc_1', true);
      notifier.update('acc_2', false);
      notifier.update('acc_3', false);
      notifier.update('acc_3', false);

      expect(notifier.state['acc_1']!.health, AccountHealth.good);
      expect(notifier.state['acc_2']!.health, AccountHealth.warning);
      expect(notifier.state['acc_3']!.health, AccountHealth.error);
    });

    test('updating one account does not affect others', () {
      notifier.update('acc_1', true);
      notifier.update('acc_2', true);

      notifier.update('acc_1', false);
      expect(notifier.state['acc_1']!.health, AccountHealth.warning);
      expect(notifier.state['acc_2']!.health, AccountHealth.good);
    });

    test('success after expired resets to good', () {
      notifier.setExpired('acc_1');
      expect(notifier.state['acc_1']!.consecutiveFailures, 99);

      notifier.update('acc_1', true);
      final status = notifier.state['acc_1']!;
      expect(status.health, AccountHealth.good);
      expect(status.consecutiveFailures, 0);
    });
  });

  group('AccountFetchStatus', () {
    test('default constructor has unknown health', () {
      const status = AccountFetchStatus();
      expect(status.health, AccountHealth.unknown);
      expect(status.consecutiveFailures, 0);
    });

    test('constructor with parameters', () {
      const status = AccountFetchStatus(
        health: AccountHealth.error,
        consecutiveFailures: 5,
      );
      expect(status.health, AccountHealth.error);
      expect(status.consecutiveFailures, 5);
    });
  });

  group('AccountHealth enum', () {
    test('has all expected values', () {
      expect(AccountHealth.values, contains(AccountHealth.unknown));
      expect(AccountHealth.values, contains(AccountHealth.good));
      expect(AccountHealth.values, contains(AccountHealth.warning));
      expect(AccountHealth.values, contains(AccountHealth.error));
      expect(AccountHealth.values.length, 4);
    });
  });
}
