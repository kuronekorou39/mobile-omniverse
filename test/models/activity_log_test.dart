import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/activity_log.dart';
import 'package:mobile_omniverse/models/sns_service.dart';

void main() {
  group('ActivityLog', () {
    group('actionLabel', () {
      test('like → いいね', () {
        final log = _makeLog(ActivityAction.like);
        expect(log.actionLabel, 'いいね');
      });

      test('unlike → いいね解除', () {
        final log = _makeLog(ActivityAction.unlike);
        expect(log.actionLabel, 'いいね解除');
      });

      test('repost → リポスト', () {
        final log = _makeLog(ActivityAction.repost);
        expect(log.actionLabel, 'リポスト');
      });

      test('unrepost → リポスト解除', () {
        final log = _makeLog(ActivityAction.unrepost);
        expect(log.actionLabel, 'リポスト解除');
      });

      test('timelineFetch → TL取得', () {
        final log = _makeLog(ActivityAction.timelineFetch);
        expect(log.actionLabel, 'TL取得');
      });

      test('follow → フォロー', () {
        final log = _makeLog(ActivityAction.follow);
        expect(log.actionLabel, 'フォロー');
      });

      test('unfollow → フォロー解除', () {
        final log = _makeLog(ActivityAction.unfollow);
        expect(log.actionLabel, 'フォロー解除');
      });

      test('post → 投稿', () {
        final log = _makeLog(ActivityAction.post);
        expect(log.actionLabel, '投稿');
      });

      test('profileFetch → プロフィール取得', () {
        final log = _makeLog(ActivityAction.profileFetch);
        expect(log.actionLabel, 'プロフィール取得');
      });
    });

    group('statusLabel', () {
      test('success: true → OK', () {
        final log = _makeLog(ActivityAction.like, success: true);
        expect(log.statusLabel, 'OK');
      });

      test('success: false → FAIL', () {
        final log = _makeLog(ActivityAction.like, success: false);
        expect(log.statusLabel, 'FAIL');
      });
    });

    test('全フィールドの保持', () {
      final ts = DateTime(2024, 1, 15, 12, 0, 0);
      final log = ActivityLog(
        timestamp: ts,
        action: ActivityAction.like,
        platform: SnsService.x,
        accountHandle: '@test',
        accountId: 'acc_1',
        targetId: 'tweet_123',
        targetSummary: 'Hello world...',
        success: true,
        statusCode: 200,
        errorMessage: null,
        responseSnippet: '{"data":{}}',
      );

      expect(log.timestamp, ts);
      expect(log.action, ActivityAction.like);
      expect(log.platform, SnsService.x);
      expect(log.accountHandle, '@test');
      expect(log.accountId, 'acc_1');
      expect(log.targetId, 'tweet_123');
      expect(log.targetSummary, 'Hello world...');
      expect(log.success, true);
      expect(log.statusCode, 200);
      expect(log.errorMessage, isNull);
      expect(log.responseSnippet, '{"data":{}}');
    });
  });
}

ActivityLog _makeLog(
  ActivityAction action, {
  bool success = true,
}) {
  return ActivityLog(
    timestamp: DateTime.now(),
    action: action,
    platform: SnsService.x,
    accountHandle: '@test',
    success: success,
  );
}
