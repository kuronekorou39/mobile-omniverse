import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/follow_user.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/follow_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 1 人ずつ取り直す情報（誕生日・最近の投稿日）の保存と集計
void main() {
  final db = FollowDb.instance;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    db.factoryOverride = databaseFactoryFfi;
    db.pathOverride = inMemoryDatabasePath;
  });

  tearDown(() async {
    await db.close();
    db.factoryOverride = null;
    db.pathOverride = null;
  });

  FollowUser user(String id) =>
      FollowUser(restId: id, screenName: 'user$id', name: 'U$id');

  Future<FollowSnapshot> completed(String kind, List<FollowUser> users) async {
    final id = await db.startSnapshot(
        service: SnsService.x, targetHandle: 'alice', kind: kind);
    await db.addBatch(snapshotId: id, users: users, cursor: '0|end');
    await db.finishSnapshot(snapshotId: id, completed: true, reason: 'end');
    return (await db.latestCompleted(SnsService.x, 'alice', kind))!;
  }

  final t0 = DateTime(2026, 10, 1);
  final fresh = DateTime(2026, 9, 24).millisecondsSinceEpoch;

  group('起点', () {
    test('フォロー・フォロワー・相互で人が決まる', () async {
      final followers = await completed('followers', [user('1'), user('2')]);
      final following = await completed('following', [user('2'), user('3')]);

      Future<int> count(String origin) async => (await db.detailCoverage(
            FollowDb.memberSetFor(origin,
                followers: followers, following: following)!,
          ))
              .total;

      expect(await count('followers'), 2);
      expect(await count('following'), 2);
      expect(await count('mutual'), 1);
    });

    test('一覧が無ければ起点を作れない', () {
      expect(FollowDb.memberSetFor('followers'), isNull);
      expect(FollowDb.memberSetFor('mutual', followers: null), isNull);
    });
  });

  group('調べる人の選び方', () {
    test('まだ調べていない人と、古くなった人だけ', () async {
      final s = await completed('following', [user('1'), user('2'), user('3')]);
      final m = FollowDb.memberSetFor('following', following: s)!;
      // 1 は新しい、2 は古い、3 は未
      await db.upsertUserDetail('1',
          profile: (month: 1, day: 2, year: null), now: DateTime(2026, 9, 30));
      await db.upsertUserDetail('2',
          profile: (month: 1, day: 2, year: null), now: DateTime(2026, 8, 1));

      final c = await db.detailCandidates(m,
          wantBirthday: true, wantLastPost: false, freshAfterMs: fresh);
      expect(c.map((e) => e.restId), ['2', '3']);
    });

    test('欲しい項目だけを見る', () async {
      final s = await completed('following', [user('1')]);
      final m = FollowDb.memberSetFor('following', following: s)!;
      await db.upsertUserDetail('1',
          profile: (month: 1, day: 2, year: null), now: t0);

      // 誕生日は済んでいるので要らない
      expect(
          await db.detailCandidates(m,
              wantBirthday: true, wantLastPost: false, freshAfterMs: fresh),
          isEmpty);
      // 投稿はまだ
      expect(
          (await db.detailCandidates(m,
                  wantBirthday: false, wantLastPost: true, freshAfterMs: fresh))
              .length,
          1);
      expect(
          await db.detailCandidates(m,
              wantBirthday: false, wantLastPost: false, freshAfterMs: fresh),
          isEmpty);
    });
  });

  group('保存', () {
    test('まとまりごとに置き換え、渡さなかった方は残る', () async {
      await db.upsertUserDetail('1',
          profile: (month: 4, day: 6, year: 1990), now: t0);
      await db.upsertUserDetail('1',
          posts: (last: DateTime(2026, 9, 1), lastOwn: DateTime(2026, 8, 1)),
          now: t0);

      final d = (await db.userDetail('1'))!;
      expect(d.birthMonth, 4);
      expect(d.birthDay, 6);
      expect(d.birthYear, 1990);
      expect(d.lastPostAt, DateTime(2026, 9, 1));
      expect(d.lastOwnPostAt, DateTime(2026, 8, 1));
      expect(d.profileFetchedAt, t0);
      expect(d.postsFetchedAt, t0);
    });

    test('分からなかったことも「調べた」として残る', () async {
      await db.upsertUserDetail('1',
          profile: (month: null, day: null, year: null), now: t0);
      final d = (await db.userDetail('1'))!;
      expect(d.hasBirthday, isFalse);
      expect(d.profileFetchedAt, t0);
    });

    test('失敗の理由は次に成功したら消える', () async {
      await db.upsertUserDetail('1',
          posts: (last: null, lastOwn: null), error: '鍵', now: t0);
      expect((await db.userDetail('1'))!.error, '鍵');
      await db.upsertUserDetail('1',
          posts: (last: DateTime(2026, 9, 1), lastOwn: null),
          clearError: true,
          now: t0);
      expect((await db.userDetail('1'))!.error, isNull);
    });

    test('本人の行が消えたら道連れになる', () async {
      await completed('following', [user('1')]);
      await db.upsertUserDetail('1',
          profile: (month: 1, day: 1, year: null), now: t0);
      await db.deleteTarget(SnsService.x, 'alice');
      await db.pruneOrphanUsers();
      expect(await db.userDetail('1'), isNull);
    });
  });

  group('集計', () {
    test('調べた人数と分かった人数を分ける', () async {
      final s = await completed('following', [user('1'), user('2'), user('3')]);
      final m = FollowDb.memberSetFor('following', following: s)!;
      await db.upsertUserDetail('1',
          profile: (month: 1, day: 1, year: null),
          posts: (last: DateTime(2026, 9, 1), lastOwn: null),
          now: t0);
      await db.upsertUserDetail('2',
          profile: (month: null, day: null, year: null),
          posts: (last: null, lastOwn: null),
          now: t0);

      final c = await db.detailCoverage(m);
      expect(c.total, 3);
      expect(c.profileFetched, 2);
      expect(c.birthdayKnown, 1);
      expect(c.postsFetched, 2);
      expect(c.lastPostKnown, 1);
    });

    test('誕生日は月・日の順に並ぶ', () async {
      final s = await completed('following', [user('1'), user('2'), user('3')]);
      final m = FollowDb.memberSetFor('following', following: s)!;
      await db.upsertUserDetail('1',
          profile: (month: 12, day: 1, year: null), now: t0);
      await db.upsertUserDetail('2',
          profile: (month: 3, day: 20, year: 1995), now: t0);
      await db.upsertUserDetail('3',
          profile: (month: 3, day: 5, year: null), now: t0);

      final b = await db.birthdays(m);
      expect(b.map((e) => e.user.restId), ['3', '2', '1']);
      expect(b[1].year, 1995);
    });

    test('最近の投稿日は古い順、投稿なしが先頭', () async {
      final s = await completed(
          'following', [user('1'), user('2'), user('3'), user('4')]);
      final m = FollowDb.memberSetFor('following', following: s)!;
      await db.upsertUserDetail('1',
          posts: (last: DateTime(2026, 9, 1), lastOwn: null), now: t0);
      await db.upsertUserDetail('2',
          posts: (last: DateTime(2024, 1, 1), lastOwn: null), now: t0);
      await db.upsertUserDetail('3',
          posts: (last: null, lastOwn: null), now: t0);
      // 4 はまだ調べていないので出ない

      final all = await db.lastPosts(m);
      expect(all.map((e) => e.user.restId), ['3', '2', '1']);

      final old = await db.lastPosts(m,
          olderThanMs: DateTime(2026, 1, 1).millisecondsSinceEpoch);
      expect(old.map((e) => e.user.restId), ['3', '2']);
    });
  });
}
