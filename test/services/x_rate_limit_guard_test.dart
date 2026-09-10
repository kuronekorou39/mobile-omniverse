import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/services/x_rate_limit_guard.dart';

void main() {
  final guard = XRateLimitGuard.instance;

  setUp(guard.clear);
  tearDown(guard.clear);

  test('429 を受けるまではクールダウンしない', () {
    expect(guard.isCoolingDown('a:HomeLatestTimeline'), isFalse);
    expect(guard.remaining('a:HomeLatestTimeline'), isNull);
  });

  test('429 で待ちに入り、連続するほど長くなる', () {
    const key = 'a:HomeLatestTimeline';

    expect(guard.recordRateLimited(key), const Duration(minutes: 1));
    expect(guard.isCoolingDown(key), isTrue);

    expect(guard.recordRateLimited(key), const Duration(minutes: 2));
    expect(guard.recordRateLimited(key), const Duration(minutes: 5));
    expect(guard.recordRateLimited(key), const Duration(minutes: 15));
    // 上限で頭打ちになる
    expect(guard.recordRateLimited(key), const Duration(minutes: 15));
  });

  test('成功したら待ちも連続回数も忘れる', () {
    const key = 'a:Notifications';
    guard.recordRateLimited(key);
    guard.recordRateLimited(key);
    expect(guard.isCoolingDown(key), isTrue);

    guard.recordSuccess(key);
    expect(guard.isCoolingDown(key), isFalse);

    // 連続回数もリセットされているので、また 1 分から始まる
    expect(guard.recordRateLimited(key), const Duration(minutes: 1));
  });

  test('retry-after が長ければそちらに従う', () {
    const key = 'a:Likes';
    final wait = guard.recordRateLimited(key,
        retryAfter: const Duration(minutes: 10));
    expect(wait, const Duration(minutes: 10));
  });

  test('retry-after が短ければ自前のバックオフを使う', () {
    const key = 'a:Likes';
    final wait =
        guard.recordRateLimited(key, retryAfter: const Duration(seconds: 5));
    expect(wait, const Duration(minutes: 1));
  });

  test('壊れた retry-after は 15 分で頭打ちにする', () {
    const key = 'a:Likes';
    final wait =
        guard.recordRateLimited(key, retryAfter: const Duration(days: 1));
    expect(wait, const Duration(minutes: 15));
  });

  test('待ちはアカウントとオペレーションの組ごとに独立している', () {
    final a = XCredentials(authToken: 'tokenAAAAAAA', ct0: 'c');
    final b = XCredentials(authToken: 'tokenBBBBBBB', ct0: 'c');

    final aTimeline = XRateLimitGuard.keyFor(a, 'HomeLatestTimeline');
    final aNotif = XRateLimitGuard.keyFor(a, 'Notifications');
    final bTimeline = XRateLimitGuard.keyFor(b, 'HomeLatestTimeline');

    guard.recordRateLimited(aNotif);

    expect(guard.isCoolingDown(aNotif), isTrue);
    expect(guard.isCoolingDown(aTimeline), isFalse);
    expect(guard.isCoolingDown(bTimeline), isFalse);
  });

  test('activeCooldowns は待機中のキーだけ返す', () {
    guard.recordRateLimited('a:Likes');
    expect(guard.activeCooldowns.keys, ['a:Likes']);

    guard.recordSuccess('a:Likes');
    expect(guard.activeCooldowns, isEmpty);
  });
}
