import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/follow_user.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/block_popular_builder.dart';
import 'package:mobile_omniverse/services/follow_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 集計表ができる前の調査を、裏で起点ごとに積み直す
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

  // 関係が 1 つも取れていない相手は記録されないので、調べた印を付ける
  FollowUser user(String id) => FollowUser(
      restId: id, screenName: 'user$id', name: 'U$id', blockedBy: false);

  /// 人気を積まずに書いて、走査を終えた＝昔の調査
  Future<int> legacyRun(int sources) async {
    final list = [for (var i = 1; i <= sources; i++) user('$i')];
    final snapshotId = await db.startSnapshot(
        service: SnsService.x, targetHandle: 'alice', kind: 'following');
    await db.addBatch(snapshotId: snapshotId, users: list, cursor: null);
    final runId = await db.startBlockRun(
        service: SnsService.x,
        targetHandle: 'alice',
        origin: 'following',
        sources: list);
    for (final s in list) {
      await db.addBlockFindings(
        runId: runId,
        sourceRestId: s.restId,
        keepPopular: false,
        users: [user('10'), user('1${s.restId}')],
      );
      await db.finishBlockSource(runId, s.restId, status: 'done');
    }
    final raw = await db.debugDatabase();
    await raw.update('block_sources', {'aggregated': 0},
        where: 'runId = ?', whereArgs: [runId]);
    return runId;
  }

  test('反映していない起点を全部積み、進み具合を知らせる', () async {
    final runId = await legacyRun(3);
    final builder = BlockPopularBuilder.instance;
    final seen = <(int, int)>[];
    void listen() {
      final p = builder.progress.value;
      if (p != null) seen.add((p.done, p.total));
    }

    builder.progress.addListener(listen);
    await builder.ensureBuilt(runId);
    builder.progress.removeListener(listen);

    expect(seen.first, (0, 3));
    expect(seen.last, (3, 3));
    expect(builder.isRunning, isFalse, reason: '終わったら知らせを消す');

    final rows = await db.popularAmongSources(runId: runId);
    expect(rows.first.user.restId, '10');
    expect(rows.first.sourceCount, 3);
    expect(rows.skip(1).map((r) => r.sourceCount), everyElement(1));
  });

  test('反映済みの調査では何もしない', () async {
    final runId = await legacyRun(1);
    await BlockPopularBuilder.instance.ensureBuilt(runId);
    final before = await db.popularAmongSources(runId: runId);
    await BlockPopularBuilder.instance.ensureBuilt(runId);
    final after = await db.popularAmongSources(runId: runId);
    expect(after.map((r) => r.sourceCount), before.map((r) => r.sourceCount));
  });
}
