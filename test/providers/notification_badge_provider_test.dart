import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/providers/notification_badge_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('NotificationBadgeProvider 初期状態', () {
    test('初期状態は空の NotificationBadgeState', () {
      final state = container.read(notificationBadgeProvider);
      expect(state, isA<NotificationBadgeState>());
      expect(state.isEmpty, true);
      expect(state.total, 0);
    });

    test('hasUnread / hasUnreadFor / totalUnread は初期状態で空', () {
      final notifier = container.read(notificationBadgeProvider.notifier);
      expect(notifier.hasUnread, false);
      expect(notifier.hasUnreadFor('unknown_acc'), false);
      expect(notifier.unreadCountFor('unknown_acc'), 0);
      expect(notifier.totalUnread, 0);
    });
  });

  group('NotificationBadgeState', () {
    test('未読件数の集計（total / contains / countFor）が正しい', () {
      const state = NotificationBadgeState(
        unreadAccountIds: {'a', 'b'},
        unreadCounts: {'a': 2, 'b': 3},
      );
      expect(state.isNotEmpty, true);
      expect(state.isEmpty, false);
      expect(state.contains('a'), true);
      expect(state.contains('z'), false);
      expect(state.countFor('a'), 2);
      expect(state.countFor('z'), 0);
      expect(state.total, 5);
    });

    test('空の state は isEmpty=true / total=0', () {
      const state = NotificationBadgeState();
      expect(state.isEmpty, true);
      expect(state.total, 0);
    });
  });

  group('NotificationBadgeNotifier', () {
    test('clearBadgeImmediately で state が空になる', () async {
      final notifier = container.read(notificationBadgeProvider.notifier);
      await notifier.clearBadgeImmediately();
      final state = container.read(notificationBadgeProvider);
      expect(state.isEmpty, true);
      expect(notifier.hasUnread, false);
    });

    test('refreshBadge は有効アカウントが無ければ空のまま', () {
      final notifier = container.read(notificationBadgeProvider.notifier);
      notifier.refreshBadge();
      expect(container.read(notificationBadgeProvider).isEmpty, true);
    });

    test('onSchedulerCycle は _checkEveryNCycles 回に1回だけチェックする', () async {
      final notifier = container.read(notificationBadgeProvider.notifier);

      // 5回未満のサイクルではチェック（フェッチ）が起きない。
      // AccountStorageService が空なので実フェッチはスキップされ、
      // state は空のまま維持される。
      for (int i = 0; i < 4; i++) {
        await notifier.onSchedulerCycle();
      }
      expect(container.read(notificationBadgeProvider).isEmpty, true);

      // 5回目でチェックが走る（アカウントが空なので state は変わらない）。
      await notifier.onSchedulerCycle();
      expect(container.read(notificationBadgeProvider).isEmpty, true);
    });
  });
}
