import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/follow_user.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/follow_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ブロック調査の保存と集計。
///
/// 数時間走らせてから集計が間違っていたと分かるのが一番まずいので、
/// 途中で見る数字と一覧の中身が食い違わないことを確かめる。
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

  FollowUser user(
    String id, {
    String? screenName,
    int friends = 0,
    int followers = 0,
    bool? blockedBy,
    bool? blocking,
    bool? muting,
  }) =>
      FollowUser(
        restId: id,
        screenName: screenName ?? 'user$id',
        name: 'U$id',
        friendsCount: friends,
        followersCount: followers,
        blockedBy: blockedBy,
        blocking: blocking,
        muting: muting,
      );

  /// 起点の人たちを users にも入れておく (一覧の JOIN 先になる)
  Future<int> startRun(List<FollowUser> sources) async {
    final snapshotId = await db.startSnapshot(
        service: SnsService.x, targetHandle: 'alice', kind: 'following');
    await db.addBatch(snapshotId: snapshotId, users: sources, cursor: null);
    return db.startBlockRun(
      service: SnsService.x,
      targetHandle: 'alice',
      origin: 'following',
      sources: sources,
    );
  }

  group('走査対象の作成', () {
    test('起点の並び順どおりに積む', () async {
      final runId = await startRun([user('1'), user('2'), user('3')]);

      final first = await db.nextBlockSource(runId);
      expect(first!.restId, '1');
      expect(first.status, 'pending');
    });

    test('フォローが多すぎる相手は最初から外す', () async {
      final runId = await startRun([
        user('1', friends: 10001),
        user('2', friends: 500),
      ]);

      // 上限超えは飛ばして次の人が来る
      expect((await db.nextBlockSource(runId))!.restId, '2');

      final p = await db.blockRunProgress(runId);
      expect(p.totalSources, 2);
      expect(p.skippedSources, 1);
      // 飛ばした人も「済み」として数える。でないと終わらない
      expect(p.doneSources, 1);
    });

    test('上限ちょうどは外さない', () async {
      final runId = await startRun([user('1', friends: 10000)]);
      expect((await db.nextBlockSource(runId))!.restId, '1');
    });
  });

  group('中断と再開', () {
    test('中断した相手を次に優先して返す', () async {
      final runId = await startRun([user('1'), user('2'), user('3')]);

      // 2 人目まで終わらせて、3 人目を途中で止めた状態にする
      await db.finishBlockSource(runId, '1', status: 'done');
      await db.markBlockSourceRunning(runId, '3');

      // 並び順では 2 が先だが、中断した 3 を先に片付ける
      expect((await db.nextBlockSource(runId))!.restId, '3');
    });

    test('cursor と件数が保存され、続きから読める', () async {
      final runId = await startRun([user('1')]);
      await db.addBlockFindings(
        runId: runId,
        sourceRestId: '1',
        users: [user('10', blockedBy: false), user('11', blockedBy: true)],
        cursor: 'c1',
      );

      final s = await db.nextBlockSource(runId);
      expect(s!.cursor, 'c1');
      expect(s.collected, 2);
    });

    test('続きを足しても件数が積み上がる', () async {
      final runId = await startRun([user('1')]);
      await db.addBlockFindings(
          runId: runId,
          sourceRestId: '1',
          users: [user('10', blockedBy: false)],
          cursor: 'c1');
      await db.addBlockFindings(
          runId: runId,
          sourceRestId: '1',
          users: [user('11', blockedBy: false)],
          cursor: 'c2');

      final s = await db.nextBlockSource(runId);
      expect(s!.collected, 2);
      expect(s.cursor, 'c2');
    });

    test('全員終われば次は無い', () async {
      final runId = await startRun([user('1'), user('2')]);
      await db.finishBlockSource(runId, '1', status: 'done');
      await db.finishBlockSource(runId, '2', status: 'failed', reason: 'x');
      expect(await db.nextBlockSource(runId), isNull);
    });
  });

  group('関係の記録', () {
    test('関係が 1 つも取れていない相手は記録しない', () async {
      final runId = await startRun([user('1')]);
      await db.addBlockFindings(
        runId: runId,
        sourceRestId: '1',
        // 関係の項目がまったく無い = 調べられていない
        users: [user('10'), user('11', blockedBy: false)],
      );

      final p = await db.blockRunProgress(runId);
      // 「いずれでもない」と「取れていない」を混ぜない
      expect(p.scanned, 1);
    });

    test('ブロック・被ブロック・ミュートを数える', () async {
      final runId = await startRun([user('1')]);
      await db.addBlockFindings(runId: runId, sourceRestId: '1', users: [
        user('10', blockedBy: true),
        user('11', blocking: true),
        user('12', muting: true),
        user('13', blockedBy: false),
      ]);

      final p = await db.blockRunProgress(runId);
      expect(p.blockedBy, 1);
      expect(p.blocking, 1);
      expect(p.muting, 1);
      expect(p.scanned, 4);
    });

    test('同じ相手が複数の起点から見つかっても 1 人と数える', () async {
      final runId = await startRun([user('1'), user('2')]);
      for (final src in ['1', '2']) {
        await db.addBlockFindings(
            runId: runId,
            sourceRestId: src,
            users: [user('10', blockedBy: true)]);
      }

      final p = await db.blockRunProgress(runId);
      expect(p.blockedBy, 1, reason: '延べではなく人数');

      final rows =
          await db.blockFindings(runId: runId, relation: 'blockedBy');
      expect(rows.length, 1);
      expect(rows.single.sourceCount, 2, reason: '2 人のフォロー先に居た');
    });
  });

  group('一覧', () {
    test('見つかった人数の多い順に並ぶ', () async {
      final runId = await startRun([user('1'), user('2'), user('3')]);
      // 10 は 3 人から、11 は 1 人から見つかる
      for (final src in ['1', '2', '3']) {
        await db.addBlockFindings(
            runId: runId,
            sourceRestId: src,
            users: [user('10', blockedBy: true)]);
      }
      await db.addBlockFindings(
          runId: runId,
          sourceRestId: '1',
          users: [user('11', blockedBy: true)]);

      final rows =
          await db.blockFindings(runId: runId, relation: 'blockedBy');
      expect(rows.map((r) => r.user.restId), ['10', '11']);
      expect(rows.first.sourceCount, 3);
    });

    test('発見元の @ID が入る', () async {
      final runId = await startRun([user('1', screenName: 'alpha')]);
      await db.addBlockFindings(
          runId: runId,
          sourceRestId: '1',
          users: [user('10', blockedBy: true)]);

      final rows =
          await db.blockFindings(runId: runId, relation: 'blockedBy');
      expect(rows.single.sourceNames, contains('alpha'));
    });

    test('種別ごとに分かれる', () async {
      final runId = await startRun([user('1')]);
      await db.addBlockFindings(runId: runId, sourceRestId: '1', users: [
        user('10', blockedBy: true),
        user('11', blocking: true),
      ]);

      expect(
          (await db.blockFindings(runId: runId, relation: 'blockedBy'))
              .map((r) => r.user.restId),
          ['10']);
      expect(
          (await db.blockFindings(runId: runId, relation: 'blocking'))
              .map((r) => r.user.restId),
          ['11']);
    });

    test('絞り込みが効く', () async {
      final runId = await startRun([user('1')]);
      await db.addBlockFindings(runId: runId, sourceRestId: '1', users: [
        user('10', screenName: 'alpha', blockedBy: true),
        user('11', screenName: 'beta', blockedBy: true),
      ]);

      final rows = await db.blockFindings(
          runId: runId,
          relation: 'blockedBy',
          filter: const FollowFilter(search: 'alph'));
      expect(rows.map((r) => r.user.restId), ['10']);
    });
  });

  group('人気の集計', () {
    test('つながっている人の間で何人からフォローされているか', () async {
      final runId = await startRun([user('1'), user('2')]);
      for (final src in ['1', '2']) {
        await db.addBlockFindings(runId: runId, sourceRestId: src, users: [
          user('10', blockedBy: false),
          user('11', blockedBy: false),
        ]);
      }
      await db.addBlockFindings(
          runId: runId,
          sourceRestId: '1',
          users: [user('12', blockedBy: false)]);

      final rows = await db.popularAmongSources(runId: runId);
      expect(rows.first.sourceCount, 2);
      expect(rows.map((r) => r.user.restId), containsAll(['10', '11', '12']));
    });

    test('自分がフォローしている相手を外せる', () async {
      // 起点に居る = 自分がフォローしている
      final runId = await startRun([user('1'), user('2')]);
      await db.addBlockFindings(runId: runId, sourceRestId: '1', users: [
        user('2', blockedBy: false), // 起点にも居る
        user('10', blockedBy: false), // 起点に居ない
      ]);

      final all = await db.popularAmongSources(runId: runId);
      expect(all.map((r) => r.user.restId), containsAll(['2', '10']));

      final unfollowed =
          await db.popularAmongSources(runId: runId, onlyNotFollowed: true);
      expect(unfollowed.map((r) => r.user.restId), ['10']);
    });
  });

  group('調査の記録', () {
    test('対象で絞って新しい順に返る', () async {
      final a = await startRun([user('1')]);
      await db.finishBlockRun(a, completed: true);
      final b = await startRun([user('2')]);

      final runs = await db.listBlockRuns(
          service: SnsService.x, targetHandle: 'alice');
      expect(runs.map((r) => r.id), [b, a]);
      expect(runs.last.isCompleted, isTrue);
      expect(runs.first.status, 'running');
    });

    test('起点の呼び名が出る', () async {
      final runId = await db.startBlockRun(
        service: SnsService.x,
        targetHandle: 'alice',
        origin: 'mutual',
        sources: [user('1')],
      );
      final run = (await db.listBlockRuns()).firstWhere((r) => r.id == runId);
      expect(run.originLabel, '相互');
    });
  });
}
