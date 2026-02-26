import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/post.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/services/timeline_fetch_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_data.dart';

void main() {
  final scheduler = TimelineFetchScheduler.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // AccountStorageService をクリーンな状態にする
    await AccountStorageService.instance.load();
    // テスト前にスケジューラを停止してクリーンな状態にする
    scheduler.stop();
    scheduler.onPostsFetched = null;
    scheduler.onFetchLog = null;
    scheduler.onTokenRefresh = null;
    scheduler.onTokenExpired = null;
  });

  tearDown(() {
    // テスト後にスケジューラを確実に停止
    scheduler.stop();
  });

  group('TimelineFetchScheduler - 基本動作', () {
    test('シングルトンインスタンスが取得できる', () {
      expect(TimelineFetchScheduler.instance, isNotNull);
      expect(TimelineFetchScheduler.instance, same(scheduler));
    });

    test('初期状態は停止中', () {
      expect(scheduler.isRunning, false);
    });

    test('start で isRunning が true になる', () {
      scheduler.start();
      expect(scheduler.isRunning, true);
      scheduler.stop();
    });

    test('stop で isRunning が false になる', () {
      scheduler.start();
      expect(scheduler.isRunning, true);

      scheduler.stop();
      expect(scheduler.isRunning, false);
    });

    test('stop を二重に呼んでも問題ない', () {
      scheduler.stop();
      scheduler.stop();
      expect(scheduler.isRunning, false);
    });

    test('start → stop → start の繰り返しが動作する', () {
      scheduler.start();
      expect(scheduler.isRunning, true);

      scheduler.stop();
      expect(scheduler.isRunning, false);

      scheduler.start();
      expect(scheduler.isRunning, true);

      scheduler.stop();
    });
  });

  group('TimelineFetchScheduler - setInterval', () {
    test('setInterval でインターバルを変更できる', () {
      scheduler.setInterval(const Duration(seconds: 30));
      // インターバルが変更されたことを直接確認する方法はないが、
      // 例外が出ないことを確認
      expect(scheduler.isRunning, false);
    });

    test('setInterval は停止中でもエラーにならない', () {
      expect(scheduler.isRunning, false);
      scheduler.setInterval(const Duration(seconds: 120));
      expect(scheduler.isRunning, false);
    });

    test('setInterval は実行中の場合にリスタートする', () {
      scheduler.start();
      expect(scheduler.isRunning, true);

      scheduler.setInterval(const Duration(seconds: 30));
      // リスタートされるが isRunning は true のまま
      expect(scheduler.isRunning, true);

      scheduler.stop();
    });
  });

  group('TimelineFetchScheduler - コールバック', () {
    test('onPostsFetched コールバックを設定できる', () {
      List<Post>? receivedPosts;
      scheduler.onPostsFetched = (posts) {
        receivedPosts = posts;
      };

      // コールバックを直接呼んでテスト
      scheduler.onPostsFetched?.call([makePost(id: 'cb_test')]);
      expect(receivedPosts, isNotNull);
      expect(receivedPosts!.length, 1);
      expect(receivedPosts!.first.id, 'cb_test');
    });

    test('onFetchLog コールバックを設定できる', () {
      String? logHandle;
      SnsService? logPlatform;
      bool? logSuccess;
      int? logCount;
      String? logError;

      scheduler.onFetchLog = (handle, platform, success, count, error) {
        logHandle = handle;
        logPlatform = platform;
        logSuccess = success;
        logCount = count;
        logError = error;
      };

      scheduler.onFetchLog?.call('@testuser', SnsService.x, true, 5, null);

      expect(logHandle, '@testuser');
      expect(logPlatform, SnsService.x);
      expect(logSuccess, true);
      expect(logCount, 5);
      expect(logError, isNull);
    });

    test('onFetchLog コールバック - エラー時', () {
      String? logError;
      bool? logSuccess;

      scheduler.onFetchLog = (handle, platform, success, count, error) {
        logSuccess = success;
        logError = error;
      };

      scheduler.onFetchLog
          ?.call('@testuser', SnsService.bluesky, false, 0, 'Network error');

      expect(logSuccess, false);
      expect(logError, 'Network error');
    });

    test('onTokenRefresh コールバックを設定できる', () {
      String? refreshHandle;
      bool? refreshSuccess;

      scheduler.onTokenRefresh = (handle, success) {
        refreshHandle = handle;
        refreshSuccess = success;
      };

      scheduler.onTokenRefresh?.call('@bsky.test', true);

      expect(refreshHandle, '@bsky.test');
      expect(refreshSuccess, true);
    });

    test('onTokenExpired コールバックを設定できる', () {
      String? expiredAccountId;
      String? expiredHandle;

      scheduler.onTokenExpired = (accountId, handle) {
        expiredAccountId = accountId;
        expiredHandle = handle;
      };

      scheduler.onTokenExpired?.call('acc_123', '@expired.user');

      expect(expiredAccountId, 'acc_123');
      expect(expiredHandle, '@expired.user');
    });

    test('コールバック未設定時に呼んでも例外が出ない', () {
      scheduler.onPostsFetched = null;
      scheduler.onFetchLog = null;
      scheduler.onTokenRefresh = null;
      scheduler.onTokenExpired = null;

      // null safe な呼び出し
      scheduler.onPostsFetched?.call([]);
      scheduler.onFetchLog?.call('@test', SnsService.x, true, 0, null);
      scheduler.onTokenRefresh?.call('@test', true);
      scheduler.onTokenExpired?.call('acc_1', '@test');

      // 例外なし
      expect(true, true);
    });
  });

  group('TimelineFetchScheduler - fetchAll', () {
    test('有効アカウントなしの場合に fetchAll はすぐに完了する', () async {
      // AccountStorageService にアカウントがない状態
      await scheduler.fetchAll();
      // 例外が出ないことを確認
      expect(true, true);
    });

    test('onPostsFetched が設定されていない場合でもエラーにならない', () async {
      scheduler.onPostsFetched = null;
      await scheduler.fetchAll();
      expect(true, true);
    });

    test('fetchAll with disabled accounts only skips fetch', () async {
      final disabledAccount = makeXAccount(
        id: 'x_disabled',
        isEnabled: false,
      );
      AccountStorageService.instance.setAccountsForTest([disabledAccount]);

      List<Post>? received;
      scheduler.onPostsFetched = (posts) => received = posts;

      await scheduler.fetchAll();

      // No posts fetched since account is disabled
      expect(received, isNull);
    });
  });

  group('TimelineFetchScheduler - setInterval while running', () {
    test('setInterval restarts timer and keeps running', () {
      scheduler.start();
      expect(scheduler.isRunning, true);

      // Change interval
      scheduler.setInterval(const Duration(seconds: 120));
      expect(scheduler.isRunning, true);

      // Change again
      scheduler.setInterval(const Duration(seconds: 15));
      expect(scheduler.isRunning, true);

      scheduler.stop();
      expect(scheduler.isRunning, false);
    });

    test('multiple start calls do not cause issues', () {
      scheduler.start();
      scheduler.start();
      scheduler.start();
      expect(scheduler.isRunning, true);
      scheduler.stop();
    });

    test('setInterval with very small duration', () {
      scheduler.setInterval(const Duration(milliseconds: 100));
      expect(scheduler.isRunning, false); // Not started
    });

    test('setInterval with large duration', () {
      scheduler.setInterval(const Duration(hours: 1));
      expect(scheduler.isRunning, false);
    });
  });

  group('TimelineFetchScheduler - callback chaining', () {
    test('callbacks can be reassigned', () {
      String? firstResult;
      String? secondResult;

      scheduler.onFetchLog = (handle, _, __, ___, ____) {
        firstResult = handle;
      };
      scheduler.onFetchLog?.call('@first', SnsService.x, true, 0, null);
      expect(firstResult, '@first');

      scheduler.onFetchLog = (handle, _, __, ___, ____) {
        secondResult = handle;
      };
      scheduler.onFetchLog?.call('@second', SnsService.x, true, 0, null);
      expect(secondResult, '@second');
      expect(firstResult, '@first'); // First callback not called again
    });

    test('onTokenRefresh callback with failure', () {
      bool? success;
      scheduler.onTokenRefresh = (_, s) => success = s;

      scheduler.onTokenRefresh?.call('@user', false);
      expect(success, false);
    });

    test('all callbacks can be set and called independently', () {
      int callCount = 0;

      scheduler.onPostsFetched = (_) => callCount++;
      scheduler.onFetchLog = (_, __, ___, ____, _____) => callCount++;
      scheduler.onTokenRefresh = (_, __) => callCount++;
      scheduler.onTokenExpired = (_, __) => callCount++;

      scheduler.onPostsFetched?.call([]);
      scheduler.onFetchLog?.call('@a', SnsService.x, true, 0, null);
      scheduler.onTokenRefresh?.call('@a', true);
      scheduler.onTokenExpired?.call('id', '@a');

      expect(callCount, 4);
    });
  });
}
