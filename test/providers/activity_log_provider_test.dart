import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/activity_log.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/providers/activity_log_provider.dart';

void main() {
  late ActivityLogNotifier notifier;

  setUp(() {
    notifier = ActivityLogNotifier();
  });

  group('ActivityLogNotifier', () {
    test('初期状態は空リスト', () {
      expect(notifier.state, isEmpty);
    });

    test('add でログを追加', () {
      final log = _makeLog(ActivityAction.like);
      notifier.add(log);

      expect(notifier.state.length, 1);
      expect(notifier.state.first.action, ActivityAction.like);
    });

    test('add は先頭に追加（新しい順）', () {
      notifier.add(_makeLog(ActivityAction.like));
      notifier.add(_makeLog(ActivityAction.repost));

      expect(notifier.state.first.action, ActivityAction.repost);
      expect(notifier.state.last.action, ActivityAction.like);
    });

    test('300件上限', () {
      for (int i = 0; i < 310; i++) {
        notifier.add(_makeLog(ActivityAction.like));
      }

      expect(notifier.state.length, 300);
    });

    test('logAction でログを追加', () {
      notifier.logAction(
        action: ActivityAction.like,
        platform: SnsService.x,
        accountHandle: '@test',
        targetId: 'tweet_123',
        success: true,
        statusCode: 200,
      );

      expect(notifier.state.length, 1);
      final log = notifier.state.first;
      expect(log.action, ActivityAction.like);
      expect(log.platform, SnsService.x);
      expect(log.accountHandle, '@test');
      expect(log.targetId, 'tweet_123');
      expect(log.success, true);
      expect(log.statusCode, 200);
    });

    test('logAction でエラーログ', () {
      notifier.logAction(
        action: ActivityAction.repost,
        platform: SnsService.bluesky,
        accountHandle: '@bsky.user',
        success: false,
        errorMessage: 'Network error',
      );

      final log = notifier.state.first;
      expect(log.success, false);
      expect(log.errorMessage, 'Network error');
    });

    group('フィルタリング', () {
      setUp(() {
        notifier.logAction(
          action: ActivityAction.timelineFetch,
          platform: SnsService.x,
          accountHandle: '@x1',
          success: true,
        );
        notifier.logAction(
          action: ActivityAction.like,
          platform: SnsService.x,
          accountHandle: '@x1',
          success: true,
        );
        notifier.logAction(
          action: ActivityAction.timelineFetch,
          platform: SnsService.bluesky,
          accountHandle: '@bsky1',
          success: true,
        );
        notifier.logAction(
          action: ActivityAction.repost,
          platform: SnsService.bluesky,
          accountHandle: '@bsky1',
          success: false,
        );
      });

      test('timelineFetchLogs は TL取得ログのみ', () {
        final logs = notifier.timelineFetchLogs;
        expect(logs.length, 2);
        for (final log in logs) {
          expect(log.action, ActivityAction.timelineFetch);
        }
      });

      test('commitLogs は TL取得以外のログ', () {
        final logs = notifier.commitLogs;
        expect(logs.length, 2);
        for (final log in logs) {
          expect(log.action, isNot(ActivityAction.timelineFetch));
        }
      });
    });

    test('clear で全クリア', () {
      notifier.add(_makeLog(ActivityAction.like));
      notifier.add(_makeLog(ActivityAction.repost));
      expect(notifier.state.length, 2);

      notifier.clear();
      expect(notifier.state, isEmpty);
    });
  });
}

ActivityLog _makeLog(ActivityAction action) {
  return ActivityLog(
    timestamp: DateTime.now(),
    action: action,
    platform: SnsService.x,
    accountHandle: '@test',
    success: true,
  );
}
