import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/models/follow_user.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/models/x_rate_limit.dart';
import 'package:mobile_omniverse/services/account_pool.dart';
import 'package:mobile_omniverse/services/follow_capture_engine.dart';
import 'package:mobile_omniverse/services/x_api_service.dart';

Account _account(String id) => Account(
      id: id,
      service: SnsService.x,
      displayName: id,
      handle: '@$id',
      credentials: const XCredentials(authToken: 'token', ct0: 'ct0'),
      createdAt: DateTime(2026, 1, 1),
    );

FollowUser _user(String id) =>
    FollowUser(restId: id, screenName: 'u$id', name: 'U$id');

XFollowListPage _ok(String userId, String? cursor, {XRateLimit? rateLimit}) =>
    XFollowListPage(
      statusCode: 200,
      users: [_user(userId)],
      cursor: cursor,
      rateLimit: rateLimit,
    );

void main() {
  late FollowCaptureEngine engine;
  late List<String?> requestedCursors;
  late List<Duration> sleeps;

  /// 呼び出し回数 (0 始まり) と cursor を受け取って 1 ページ返す差し替え口
  late Future<XFollowListPage> Function(int call, String? cursor) handler;

  setUp(() {
    requestedCursors = [];
    sleeps = [];
    handler = (_, __) async => const XFollowListPage(statusCode: 200);

    var calls = 0;
    engine = FollowCaptureEngine(
      fetchPage: ({
        required Account account,
        required String targetHandle,
        required FollowListKind kind,
        String? cursor,
      }) {
        requestedCursors.add(cursor);
        return handler(calls++, cursor);
      },
    )..sleepOverride = (d) async => sleeps.add(d);
  });

  /// 呼ばれるたびに [pages] を順に返す (足りなくなったら最後を繰り返す)
  void stubPages(List<XFollowListPage> pages) {
    handler =
        (call, _) async => pages[call < pages.length ? call : pages.length - 1];
  }

  Future<FollowCaptureResult> run({
    AccountPool? pool,
    String? startCursor,
    CaptureCancelToken? cancelToken,
    Account? Function(String accountId)? accountOf,
    Future<void> Function(List<FollowUser> users, String? cursor)? onBatch,
    void Function(FollowCaptureProgress progress)? onProgress,
  }) {
    return engine.capture(
      targetHandle: 'someone',
      kind: FollowListKind.followers,
      pool: pool ?? AccountPool(['acc1'], cooldown: Duration.zero),
      accountOf: accountOf ?? _account,
      startCursor: startCursor,
      cancelToken: cancelToken,
      onBatch: onBatch,
      onProgress: onProgress,
    );
  }

  group('正常系', () {
    test('終端カーソルに到達するまでページングする', () async {
      stubPages([_ok('1', '1|a'), _ok('2', '0|end')]);

      final result = await run();

      expect(result.completed, isTrue);
      expect(result.reason, FollowCaptureReason.terminal);
      expect(result.totalUsers, 2);
      // 1回目は cursor なし、2回目は 1ページ目の cursor
      expect(requestedCursors, [null, '1|a']);
    });

    test('cursor が返らなくなったら完了扱い', () async {
      stubPages([_ok('1', null)]);

      final result = await run();

      expect(result.completed, isTrue);
      expect(result.reason, FollowCaptureReason.noCursor);
      expect(result.totalUsers, 1);
    });

    test('空バッチで cursor も動かなければ停滞として完了', () async {
      stubPages([const XFollowListPage(statusCode: 200)]);

      final result = await run();

      expect(result.completed, isTrue);
      expect(result.reason, FollowCaptureReason.stalled);
      expect(result.totalUsers, 0);
    });

    test('onBatch にページごとのユーザーが渡る', () async {
      stubPages([_ok('1', '1|a'), _ok('2', '0|end')]);
      final batches = <List<String>>[];

      await run(onBatch: (users, _) async {
        batches.add(users.map((u) => u.restId).toList());
      });

      expect(batches, [
        ['1'],
        ['2']
      ]);
    });

    test('onProgress が累計件数を通知する', () async {
      stubPages([_ok('1', '1|a'), _ok('2', '0|end')]);
      final collected = <int>[];

      await run(onProgress: (p) => collected.add(p.collected));

      expect(collected, [1, 2]);
    });
  });

  group('再開', () {
    test('startCursor がすでに終端なら 1 回も叩かない', () async {
      stubPages([_ok('1', '0|end')]);

      final result = await run(startCursor: '0|already-done');

      expect(result.completed, isTrue);
      expect(result.reason, FollowCaptureReason.terminal);
      expect(requestedCursors, isEmpty);
    });

    test('startCursor から続きを取得する', () async {
      stubPages([_ok('1', '0|end')]);

      await run(startCursor: '5|mid');

      expect(requestedCursors, ['5|mid']);
    });

    test('中断しても再開位置の cursor を返す', () async {
      stubPages([_ok('1', '1|a'), const XFollowListPage(statusCode: 401)]);

      final result = await run();

      expect(result.completed, isFalse);
      // 401 で止まったが、次回は 1|a から再開できる
      expect(result.cursor, '1|a');
      expect(result.totalUsers, 1);
    });
  });

  group('失敗時に cursor を前進させない', () {
    test('429 の後も同じ cursor で再送する', () async {
      stubPages([
        _ok('1', '1|a'),
        XFollowListPage(
          statusCode: 429,
          rateLimit: XRateLimit(
              limit: 50,
              remaining: 0,
              resetAt: DateTime.now().add(const Duration(seconds: 30))),
        ),
        _ok('2', '0|end'),
      ]);

      final result = await run();

      expect(requestedCursors, [null, '1|a', '1|a']);
      expect(result.totalUsers, 2);
      expect(result.reason, FollowCaptureReason.terminal);
      expect(sleeps, isNotEmpty);
    });

    test('5xx の後も同じ cursor で再送する', () async {
      stubPages([
        _ok('1', '1|a'),
        const XFollowListPage(statusCode: 503),
        _ok('2', '0|end'),
      ]);

      final result = await run();

      expect(requestedCursors, [null, '1|a', '1|a']);
      expect(result.reason, FollowCaptureReason.terminal);
    });
  });

  group('レート制限', () {
    test('429 は reset までの時間 + マージン待つ', () async {
      final resetAt = DateTime.now().add(const Duration(seconds: 120));
      stubPages([
        XFollowListPage(
            statusCode: 429,
            rateLimit: XRateLimit(limit: 50, remaining: 0, resetAt: resetAt)),
        _ok('1', '0|end'),
      ]);

      await run();

      // 約 120 秒 + 5 秒。テスト実行のブレを許容して幅で見る
      expect(sleeps.first.inSeconds, greaterThan(115));
      expect(sleeps.first.inSeconds, lessThanOrEqualTo(126));
    });

    test('reset 時刻が読めない 429 は既定の待ち時間', () async {
      stubPages([
        const XFollowListPage(statusCode: 429),
        _ok('1', '0|end'),
      ]);

      await run();

      expect(sleeps.first, FollowCaptureEngine.rateLimitFallbackWait);
    });

    test('残量が少なくなると送信間隔が延びる', () async {
      // 1 ページ目で残量 5% を切る → 2 ページ目の前に減速待機が入る。
      // cooldown は 0 にしておく (AccountPool は実時刻を見るため、
      // sleepOverride で待ちを潰すと cooldown 明けを空回りで待つことになる)
      stubPages([
        _ok('1', '1|a', rateLimit: const XRateLimit(limit: 100, remaining: 1)),
        _ok('2', '0|end'),
      ]);

      await run(pool: AccountPool(['acc1'], cooldown: Duration.zero));

      expect(sleeps, isNotEmpty);
      expect(sleeps.first, AccountPool.criticalFloor);
    });
  });

  group('アカウントの失効', () {
    test('401 でアカウントをプールから外し、空になったら終了', () async {
      stubPages([const XFollowListPage(statusCode: 401)]);

      final result = await run();

      expect(result.completed, isFalse);
      expect(result.reason, FollowCaptureReason.poolEmpty);
    });

    test('403 でも同様にプールから外す', () async {
      stubPages([const XFollowListPage(statusCode: 403)]);

      expect((await run()).reason, FollowCaptureReason.poolEmpty);
    });

    test('再捕獲後も 404 ならプールから外す', () async {
      stubPages([const XFollowListPage(statusCode: 404)]);

      expect((await run()).reason, FollowCaptureReason.poolEmpty);
    });

    test('JSON として読めない応答もプールから外す', () async {
      stubPages([
        const XFollowListPage(statusCode: XApiService.followListBadJson),
      ]);

      expect((await run()).reason, FollowCaptureReason.poolEmpty);
    });

    test('生きているアカウントがあれば続行する', () async {
      stubPages([
        const XFollowListPage(statusCode: 401),
        _ok('1', '0|end'),
      ]);

      final result = await run(
          pool: AccountPool(['acc1', 'acc2'], cooldown: Duration.zero));

      expect(result.completed, isTrue);
      expect(result.totalUsers, 1);
    });

    test('アカウントを引けないものは除外する', () async {
      stubPages([_ok('1', '0|end')]);

      final result = await run(
        pool: AccountPool(['dead', 'acc2'], cooldown: Duration.zero),
        accountOf: (id) => id == 'dead' ? null : _account(id),
      );

      expect(result.completed, isTrue);
      expect(result.totalUsers, 1);
    });

    test('連続失敗の上限を指定すれば circuit break する', () async {
      stubPages([const XFollowListPage(statusCode: 401)]);

      final result = await run(
        pool: AccountPool(
          ['a1', 'a2', 'a3'],
          cooldown: Duration.zero,
          consecutiveFailureLimit: 2,
        ),
      );

      expect(result.reason, FollowCaptureReason.circuitBreak);
      expect(result.completed, isFalse);
    });
  });

  group('通信エラー', () {
    test('例外が続いたら networkError で終了する', () async {
      handler = (_, __) async => throw Exception('boom');

      final result = await run();

      expect(result.completed, isFalse);
      expect(result.reason, FollowCaptureReason.networkError);
      // 上限回数ぶんは待ちながら再試行している
      expect(sleeps, hasLength(FollowCaptureEngine.maxConsecutiveNetworkErrors));
    });

    test('例外の後に成功すれば再試行カウンタが戻る', () async {
      handler = (call, _) async {
        if (call == 0) throw Exception('transient');
        return _ok('1', '0|end');
      };

      final result = await run();

      expect(result.completed, isTrue);
      expect(result.totalUsers, 1);
    });

    test('5xx が続いたら httpError で終了する', () async {
      stubPages([const XFollowListPage(statusCode: 500)]);

      final result = await run();

      expect(result.completed, isFalse);
      expect(result.reason, FollowCaptureReason.httpError);
      expect(result.httpStatus, 500);
    });
  });

  group('キャンセル', () {
    test('走査前にキャンセルされていれば即座に中断する', () async {
      stubPages([_ok('1', '1|a')]);
      final token = CaptureCancelToken()..cancel();

      final result = await run(cancelToken: token);

      expect(result.completed, isFalse);
      expect(result.reason, FollowCaptureReason.aborted);
      expect(requestedCursors, isEmpty);
    });

    test('ページング途中のキャンセルで中断し cursor を残す', () async {
      final token = CaptureCancelToken();
      handler = (call, _) async {
        if (call == 1) token.cancel();
        return _ok('${call + 1}', '${call + 1}|next');
      };

      final result = await run(cancelToken: token);

      expect(result.reason, FollowCaptureReason.aborted);
      expect(result.cursor, '2|next');
      expect(result.totalUsers, 2);
    });
  });
}
