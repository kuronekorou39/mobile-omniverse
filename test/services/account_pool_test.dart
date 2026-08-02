import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/models/x_rate_limit.dart';
import 'package:mobile_omniverse/services/account_pool.dart';

final _t0 = DateTime.utc(2026, 7, 30, 12, 0, 0);

void main() {
  group('AccountPool の選択とクールダウン', () {
    test('未使用のアカウントを優先して返す', () {
      final pool = AccountPool(['a', 'b']);
      expect(pool.pick(now: _t0), isNotNull);
      expect(pool.size, 2);
    });

    test('空文字の ID は登録しない', () {
      final pool = AccountPool(['a', '', 'b']);
      expect(pool.accountIds, ['a', 'b']);
    });

    test('クールダウン中のアカウントは選ばれない', () {
      final pool = AccountPool(['a'], cooldown: const Duration(seconds: 60));
      pool.markUsed('a', at: _t0);

      expect(pool.pick(now: _t0.add(const Duration(seconds: 59))), isNull);
      expect(pool.pick(now: _t0.add(const Duration(seconds: 60))), 'a');
    });

    test('timeUntilNext はクールダウンの残りを返す', () {
      final pool = AccountPool(['a'], cooldown: const Duration(seconds: 60));
      pool.markUsed('a', at: _t0);

      expect(pool.timeUntilNext(now: _t0.add(const Duration(seconds: 20))),
          const Duration(seconds: 40));
      // 明けていれば 0
      expect(pool.timeUntilNext(now: _t0.add(const Duration(seconds: 90))),
          Duration.zero);
    });

    test('複数アカウントは「最も古くに使ったもの」から回る', () {
      final pool = AccountPool(['a', 'b'], cooldown: const Duration(seconds: 10));
      pool.markUsed('a', at: _t0);
      pool.markUsed('b', at: _t0.add(const Duration(seconds: 5)));

      // 両方クールダウン明けの時点では、古い a が先
      final picked = pool.pick(now: _t0.add(const Duration(seconds: 20)));
      expect(picked, 'a');
    });

    test('baseInterval はアカウント数で割った値になる', () {
      expect(AccountPool(['a'], cooldown: const Duration(seconds: 60)).baseInterval,
          const Duration(seconds: 60));
      expect(
          AccountPool(['a', 'b', 'c'], cooldown: const Duration(seconds: 60))
              .baseInterval,
          const Duration(seconds: 20));
    });
  });

  group('AccountPool の適応スロットル', () {
    AccountPool poolWith(XRateLimit rl, {int accounts = 3}) {
      final pool = AccountPool(
        [for (var i = 0; i < accounts; i++) 'a$i'],
        cooldown: const Duration(seconds: 60),
      );
      pool.updateRateLimit('a0', rl);
      return pool;
    }

    test('残量が十分なら基準間隔のまま', () {
      final pool = poolWith(const XRateLimit(limit: 100, remaining: 50));
      expect(pool.dynamicInterval('a0', now: _t0), pool.baseInterval);
    });

    test('残量 15% 未満で 3 倍に減速する', () {
      final pool = poolWith(const XRateLimit(limit: 100, remaining: 10));
      // base 20秒 × 3 = 60秒
      expect(pool.dynamicInterval('a0', now: _t0), const Duration(seconds: 60));
    });

    test('減速時は下限を下回らない', () {
      final pool = AccountPool(
        ['a0'],
        cooldown: const Duration(seconds: 1),
      );
      pool.updateRateLimit('a0', const XRateLimit(limit: 100, remaining: 10));
      // base 1秒 × 3 = 3秒 → 下限 6秒に引き上げ
      expect(pool.dynamicInterval('a0', now: _t0), AccountPool.slowdownFloor);
    });

    test('残量 1 以下なら reset 時刻まで待つ', () {
      final pool = poolWith(XRateLimit(
        limit: 100,
        remaining: 1,
        resetAt: _t0.add(const Duration(minutes: 3)),
      ));
      // reset までの 3 分 + マージン 5 秒
      expect(pool.dynamicInterval('a0', now: _t0),
          const Duration(minutes: 3) + AccountPool.resetMargin);
    });

    test('残量わずかで reset 時刻が不明なら下限まで待つ', () {
      final pool = poolWith(const XRateLimit(limit: 100, remaining: 0));
      // base 20秒 × 30 = 600秒 (下限 30秒より大きいのでそのまま)
      expect(pool.dynamicInterval('a0', now: _t0), const Duration(seconds: 600));
    });

    test('レート制限情報が無ければ基準間隔', () {
      final pool = AccountPool(['a0'], cooldown: const Duration(seconds: 60));
      expect(pool.dynamicInterval('a0', now: _t0), pool.baseInterval);
    });

    test('プールに居ないアカウントのレート制限は保持しない', () {
      final pool = AccountPool(['a0']);
      pool.updateRateLimit('unknown', const XRateLimit(limit: 100, remaining: 1));
      expect(pool.rateLimitOf('unknown'), isNull);
    });
  });

  group('AccountPool の失敗管理', () {
    test('markFailed でプールから外れる', () {
      final pool = AccountPool(['a', 'b']);
      pool.markFailed('a');

      expect(pool.accountIds, ['b']);
      expect(pool.consecutiveFailures, 1);
    });

    test('連続失敗が上限に達すると circuit break', () {
      // 既定の上限はアカウント数 + 1
      final pool = AccountPool(['a', 'b']);
      expect(pool.consecutiveFailureLimit, 3);

      pool.markFailed('a');
      pool.markFailed('b');
      expect(pool.shouldCircuitBreak, isFalse);

      pool.markFailed('c'); // 既に居なくてもカウントは進む
      expect(pool.shouldCircuitBreak, isTrue);
    });

    test('markSuccess で連続失敗カウンタが戻る', () {
      final pool = AccountPool(['a', 'b', 'c']);
      pool.markFailed('a');
      pool.markSuccess();

      expect(pool.consecutiveFailures, 0);
      expect(pool.shouldCircuitBreak, isFalse);
    });

    test('全部外れると isEmpty', () {
      final pool = AccountPool(['a']);
      pool.markFailed('a');

      expect(pool.isEmpty, isTrue);
      expect(pool.pick(now: _t0), isNull);
      expect(pool.timeUntilNext(now: _t0), Duration.zero);
    });
  });

  group('AccountPool.snapshot', () {
    test('残りクールダウンとレート制限を返す', () {
      final pool = AccountPool(['a', 'b'], cooldown: const Duration(seconds: 60));
      pool.markUsed('a', at: _t0);
      pool.updateRateLimit('a', const XRateLimit(limit: 100, remaining: 90));

      final snap = pool.snapshot(now: _t0.add(const Duration(seconds: 15)));
      final a = snap.firstWhere((e) => e.accountId == 'a');
      final b = snap.firstWhere((e) => e.accountId == 'b');

      expect(a.cooldownRemaining, const Duration(seconds: 45));
      expect(a.rateLimit?.remaining, 90);
      // 未使用はクールダウン 0
      expect(b.cooldownRemaining, Duration.zero);
      expect(b.rateLimit, isNull);
    });
  });

  group('XRateLimit', () {
    test('ヘッダーから抽出する', () {
      final rl = XRateLimit.fromHeaders({
        'x-rate-limit-limit': '50',
        'x-rate-limit-remaining': '49',
        'x-rate-limit-reset': '1785412800',
      });

      expect(rl, isNotNull);
      expect(rl!.limit, 50);
      expect(rl.remaining, 49);
      expect(rl.resetAt,
          DateTime.fromMillisecondsSinceEpoch(1785412800 * 1000));
      expect(rl.remainingRatio, closeTo(0.98, 0.001));
    });

    test('3 つとも無ければ null', () {
      expect(XRateLimit.fromHeaders({'content-type': 'application/json'}),
          isNull);
    });

    test('untilReset は過ぎていれば null', () {
      final rl = XRateLimit(resetAt: _t0);
      expect(rl.untilReset(now: _t0.add(const Duration(seconds: 1))), isNull);
      expect(rl.untilReset(now: _t0.subtract(const Duration(seconds: 10))),
          const Duration(seconds: 10));
    });
  });
}
