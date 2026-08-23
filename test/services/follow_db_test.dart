import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/follow_user.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/follow_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// follow_db は sqflite (端末側のプラグイン) を使うためテスト VM では動かない。
/// FFI 版に差し替えて、本番と同じスキーマ・マイグレーションを実際に走らせる。
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

  // ───────────────────────── ヘルパー ─────────────────────────

  FollowUser user(
    String id, {
    String? screenName,
    String name = '',
    int followers = 0,
    int friends = 0,
    int? statuses,
    bool protected = false,
    bool verified = false,
  }) =>
      FollowUser(
        restId: id,
        screenName: screenName ?? 'user$id',
        name: name,
        followersCount: followers,
        friendsCount: friends,
        statusesCount: statuses,
        isProtected: protected,
        verified: verified,
      );

  /// 完了済みスナップショットを 1 本作って members を入れる。
  ///
  /// [startedAt] を渡すのは世代の並びを固定するため。startSnapshot は
  /// DateTime.now() を打つので、テストの中で連続して作ると同じミリ秒に
  /// なり「どちらが新しいか」が決まらなくなる。
  Future<int> completedSnapshot(
    String handle,
    String kind,
    List<FollowUser> users, {
    int? startedAt,
    SnsService service = SnsService.x,
  }) async {
    final id = await db.startSnapshot(
        service: service, targetHandle: handle, kind: kind);
    if (startedAt != null) {
      final raw = await db.debugDatabase();
      await raw.update('snapshots', {'startedAt': startedAt},
          where: 'id = ?', whereArgs: [id]);
    }
    await db.addBatch(snapshotId: id, users: users, cursor: '0|end');
    await db.finishSnapshot(
        snapshotId: id, completed: true, reason: 'terminal');
    return id;
  }

  Future<List<String>> tableNames() async {
    final raw = await db.debugDatabase();
    final rows =
        await raw.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<List<String>> columns(String table) async {
    final raw = await db.debugDatabase();
    final rows = await raw.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<int> countRows(String table) async {
    final raw = await db.debugDatabase();
    final rows = await raw.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// v1 相当の DB を手で作る。当時の定義をここに固定しておく
  Future<String> createLegacyV1(String prefix, String targetHandle) async {
    final dir = Directory.systemTemp.createTempSync(prefix);
    final path = '${dir.path}/follow_capture.db';
    addTearDown(() async {
      await db.close();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1),
    );
    await legacy.execute('''
      CREATE TABLE users (
        restId TEXT PRIMARY KEY, screenName TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '', followersCount INTEGER NOT NULL DEFAULT 0,
        friendsCount INTEGER NOT NULL DEFAULT 0, statusesCount INTEGER,
        avatarUrl TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '',
        verified INTEGER NOT NULL DEFAULT 0, isProtected INTEGER NOT NULL DEFAULT 0,
        location TEXT NOT NULL DEFAULT '', createdAt TEXT NOT NULL DEFAULT '',
        updatedAt INTEGER NOT NULL)
    ''');
    await legacy.execute('''
      CREATE TABLE snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT, targetHandle TEXT NOT NULL,
        kind TEXT NOT NULL, sessionAccountId TEXT, startedAt INTEGER NOT NULL,
        completedAt INTEGER, status TEXT NOT NULL, reason TEXT, cursor TEXT,
        collectedCount INTEGER NOT NULL DEFAULT 0)
    ''');
    await legacy.execute('''
      CREATE TABLE snapshot_members (
        snapshotId INTEGER NOT NULL, restId TEXT NOT NULL,
        PRIMARY KEY (snapshotId, restId))
    ''');
    await legacy.insert('snapshots', {
      'targetHandle': targetHandle,
      'kind': 'followers',
      'sessionAccountId': 'acc-1',
      'startedAt': 1000,
      'completedAt': 2000,
      'status': 'completed',
      'collectedCount': 0,
    });
    await legacy.close();
    return path;
  }

  /// 一時ファイルの DB を使う。サイズを見る処理はファイルが要る
  Future<void> useTempFile(String prefix) async {
    final dir = Directory.systemTemp.createTempSync(prefix);
    db.pathOverride = '${dir.path}/follow_capture.db';
    addTearDown(() async {
      // 接続を閉じてからでないと Windows ではファイルを消せない
      await db.close();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
  }

  // ───────────────────────── スキーマ ─────────────────────────

  group('スキーマ', () {
    test('新規作成で v4 までのテーブルと列がそろう', () async {
      await db.listTargets();

      expect(
        await tableNames(),
        containsAll(<String>['users', 'snapshots', 'snapshot_members', 'targets']),
      );
      expect(await columns('snapshots'), contains('runId'));
      expect(await columns('snapshots'), contains('totalExpected'));
      expect(await columns('snapshot_members'), contains('statusesCount'));
    });

    test('v1 の DB を開くと最新まで上がり、対象が復元される', () async {
      db.pathOverride = await createLegacyV1('follow_db_v1', 'alice');

      final targets = await db.listTargets();
      // v3 のマイグレーションが既存スナップショットから対象を起こす
      expect(targets.map((t) => t.handle), ['alice']);
      expect(targets.single.sessionAccountId, 'acc-1');
      expect(await columns('snapshots'), contains('totalExpected'));
      expect(await columns('snapshots'), contains('service'));
    });

    test('v6 より前の対象はすべて X とみなす', () async {
      db.pathOverride = await createLegacyV1('follow_db_v6', 'alice');

      // 当時は X しか扱えなかった
      expect((await db.listTargets()).single.service, SnsService.x);
      expect(
          (await db.latestCompleted(SnsService.x, 'alice', 'followers')), isNotNull);
      expect((await db.latestCompleted(SnsService.bluesky, 'alice', 'followers')),
          isNull);
    });

    test('大文字で入っていた handle は小文字にならされる', () async {
      db.pathOverride = await createLegacyV1('follow_db_case', 'Alice');

      // 引くときだけ小文字化していたため、大文字で入った行は
      // latestCompleted から見えず毎回取り直しになっていた
      expect((await db.listTargets()).map((t) => t.handle), ['alice']);
      expect(await db.latestCompleted(SnsService.x, 'alice', 'followers'), isNotNull);
      expect(await db.memberRowsByTarget(), isEmpty);
    });
  });

  // ───────────────────────── 走査対象 ─────────────────────────

  group('走査対象', () {
    test('登録・取得・上書きができる', () async {
      await db.upsertTarget(FollowTarget(
        service: SnsService.x,
        handle: 'alice',
        addedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        displayName: 'Alice',
        sessionAccountId: 'acc-1',
      ));
      final t = await db.getTarget(SnsService.x, 'alice');
      expect(t!.displayName, 'Alice');
      expect(t.followersIntervalDays, 0);

      await db.upsertTarget(t.copyWith(followersIntervalDays: 3));
      expect((await db.getTarget(SnsService.x, 'alice'))!.followersIntervalDays, 3);
      expect((await db.listTargets()).length, 1);
    });

    test('@ と大文字を落として引ける', () async {
      await db.upsertTarget(
          FollowTarget(
              service: SnsService.x,
              handle: 'alice',
              addedAt: DateTime(2026)));
      expect(await db.getTarget(SnsService.x, '@Alice'), isNotNull);
      expect(await db.getTarget(SnsService.x, 'ALICE'), isNotNull);
    });

    test('大文字で登録しても小文字にそろえて入る', () async {
      await db.upsertTarget(
          FollowTarget(
              service: SnsService.x,
              handle: '@Alice',
              addedAt: DateTime(2026)));
      expect((await db.listTargets()).map((t) => t.handle), ['alice']);
      expect(await db.getTarget(SnsService.x, 'alice'), isNotNull);
    });

    test('削除すると紐づくスナップショットと members も消える', () async {
      await db.upsertTarget(
          FollowTarget(
              service: SnsService.x,
              handle: 'alice',
              addedAt: DateTime(2026)));
      await completedSnapshot('alice', 'followers', [user('1'), user('2')]);
      await db.upsertTarget(FollowTarget(
          service: SnsService.x, handle: 'bob', addedAt: DateTime(2026)));
      await completedSnapshot('bob', 'followers', [user('3')]);

      await db.deleteTarget(SnsService.x, '@Alice');

      expect((await db.listTargets()).map((t) => t.handle), ['bob']);
      expect(await db.listSnapshots(targetHandle: 'alice'), isEmpty);
      expect(await db.memberRowsByTarget(),
          {(service: SnsService.x, handle: 'bob'): 1});
      // 参照が無くなった users も掃除される
      expect(await countRows('users'), 1);
    });

    test('同じ handle でも SNS が違えば別の対象になる', () async {
      for (final service in SnsService.values) {
        await db.upsertTarget(FollowTarget(
            service: service, handle: 'alice', addedAt: DateTime(2026)));
      }

      expect((await db.listTargets()).length, 2);
      expect((await db.getTarget(SnsService.bluesky, 'alice'))!.service,
          SnsService.bluesky);
    });

    test('片方の SNS を消してももう片方は残る', () async {
      for (final service in SnsService.values) {
        await db.upsertTarget(FollowTarget(
            service: service, handle: 'alice', addedAt: DateTime(2026)));
        await completedSnapshot('alice', 'followers', [user('1')],
            service: service);
      }

      await db.deleteTarget(SnsService.x, 'alice');

      expect((await db.listTargets()).single.service, SnsService.bluesky);
      expect(await db.latestCompleted(SnsService.x, 'alice', 'followers'),
          isNull);
      expect(await db.latestCompleted(SnsService.bluesky, 'alice', 'followers'),
          isNotNull);
    });

    test('走査も SNS ごとに分かれる', () async {
      await completedSnapshot('alice', 'followers', [user('1')],
          service: SnsService.x);
      await completedSnapshot('alice', 'followers', [user('2')],
          service: SnsService.bluesky);

      expect(
          (await db.listSnapshots(
                  service: SnsService.x, targetHandle: 'alice'))
              .length,
          1);
      expect(await db.memberRowsByTarget(), {
        (service: SnsService.x, handle: 'alice'): 1,
        (service: SnsService.bluesky, handle: 'alice'): 1,
      });
    });

    test('他の対象から参照されているユーザーは残す', () async {
      await completedSnapshot('alice', 'followers', [user('1')]);
      await completedSnapshot('bob', 'followers', [user('1')]);
      await db.deleteTarget(SnsService.x, 'alice');
      expect(await countRows('users'), 1);
    });
  });

  // ───────────────────────── 走査の記録 ─────────────────────────

  group('走査の記録', () {
    test('addBatch は cursor を進め、件数を数え直す', () async {
      final id = await db.startSnapshot(
          service: SnsService.x, targetHandle: 'alice', kind: 'followers');
      await db
          .addBatch(snapshotId: id, users: [user('1'), user('2')], cursor: 'c1');

      var s = (await db.getSnapshot(id))!;
      expect(s.collectedCount, 2);
      expect(s.cursor, 'c1');
      expect(s.status, 'running');

      await db.addBatch(snapshotId: id, users: [user('3')], cursor: 'c2');
      s = (await db.getSnapshot(id))!;
      expect(s.collectedCount, 3);
      expect(s.cursor, 'c2');
    });

    test('同じユーザーが再び現れても二重に数えない', () async {
      final id = await db.startSnapshot(
          service: SnsService.x, targetHandle: 'alice', kind: 'followers');
      await db
          .addBatch(snapshotId: id, users: [user('1'), user('2')], cursor: 'c1');
      await db
          .addBatch(snapshotId: id, users: [user('2'), user('3')], cursor: 'c2');
      expect((await db.getSnapshot(id))!.collectedCount, 3);
    });

    test('users は最新値で上書きされるが members は走査時点の値を保つ', () async {
      final old = await completedSnapshot(
          'alice', 'followers', [user('1', statuses: 100, followers: 10)],
          startedAt: 1000);
      await completedSnapshot(
          'alice', 'followers', [user('1', statuses: 150, followers: 12)],
          startedAt: 2000);

      final oldMembers = await db.members(old);
      expect(oldMembers.single.statusesCount, 100);
      expect(oldMembers.single.followersCount, 10);
    });

    test('空バッチでも cursor だけは進む', () async {
      final id = await db.startSnapshot(
          service: SnsService.x, targetHandle: 'alice', kind: 'followers');
      await db.addBatch(snapshotId: id, users: [], cursor: 'c1');
      expect((await db.getSnapshot(id))!.cursor, 'c1');
    });

    test('users も cursor も無ければ何もしない', () async {
      final id = await db.startSnapshot(
          service: SnsService.x, targetHandle: 'alice', kind: 'followers');
      await db.addBatch(snapshotId: id, users: [user('1')], cursor: 'c1');
      await db.addBatch(snapshotId: id, users: [], cursor: null);
      // 直前の cursor が null で潰されない
      expect((await db.getSnapshot(id))!.cursor, 'c1');
    });

    test('完了すると status と completedAt が入る', () async {
      final id = await db.startSnapshot(
          service: SnsService.x, targetHandle: 'alice', kind: 'followers');
      await db.addBatch(snapshotId: id, users: [user('1')], cursor: 'c1');
      await db.finishSnapshot(
          snapshotId: id, completed: true, reason: 'terminal', cursor: null);

      final s = (await db.getSnapshot(id))!;
      expect(s.isCompleted, isTrue);
      expect(s.reason, 'terminal');
      expect(s.cursor, isNull);
      expect(s.completedAt, isNotNull);
      expect(s.isResumable, isFalse);
    });

    test('中断すると cursor が残り再開候補になる', () async {
      final id = await db.startSnapshot(
          service: SnsService.x, targetHandle: 'alice', kind: 'followers');
      await db.addBatch(snapshotId: id, users: [user('1')], cursor: 'c1');
      await db.finishSnapshot(
          snapshotId: id, completed: false, reason: 'aborted', cursor: 'c1');

      final s = (await db.getSnapshot(id))!;
      expect(s.status, 'interrupted');
      expect(s.isResumable, isTrue);
      expect((await db.resumableFor(SnsService.x, 'alice')).map((e) => e.id), [id]);
    });

    test('cursor の無い中断は再開候補に出さない', () async {
      final id = await db.startSnapshot(
          service: SnsService.x, targetHandle: 'alice', kind: 'followers');
      await db.finishSnapshot(
          snapshotId: id, completed: false, reason: 'poolEmpty', cursor: null);
      expect(await db.resumableFor(SnsService.x, 'alice'), isEmpty);
    });

    test('latestCompleted は完了済みの最新だけを返す', () async {
      final first = await completedSnapshot('alice', 'followers', [user('1')],
          startedAt: 1000);
      final interrupted =
          await db.startSnapshot(
          service: SnsService.x, targetHandle: 'alice', kind: 'followers');
      await db
          .addBatch(snapshotId: interrupted, users: [user('2')], cursor: 'c');
      await db.finishSnapshot(
          snapshotId: interrupted,
          completed: false,
          reason: 'aborted',
          cursor: 'c');

      expect((await db.latestCompleted(SnsService.x, 'alice', 'followers'))!.id, first);
      expect(await db.latestCompleted(SnsService.x, 'alice', 'following'), isNull);
      expect(await db.latestCompleted(SnsService.x, 'bob', 'followers'), isNull);
    });

    test('latestCompleted は世代が増えても最新を返す', () async {
      await completedSnapshot('alice', 'followers', [user('1')], startedAt: 1000);
      final newer = await completedSnapshot('alice', 'followers', [user('2')],
          startedAt: 2000);
      expect((await db.latestCompleted(SnsService.x, 'alice', 'followers'))!.id, newer);
    });

    test('大文字の対象で始めた走査も同じ対象として引ける', () async {
      final id = await completedSnapshot('@Alice', 'followers', [user('1')]);

      // 引くときは小文字にするので、書くときもそろえないと
      // 「一度も完了していない」ことになりスケジュールが毎回発火する
      expect((await db.latestCompleted(SnsService.x, 'alice', 'followers'))!.id, id);
      expect((await db.listSnapshots(targetHandle: 'ALICE')).map((s) => s.id),
          [id]);
      expect(await db.memberRowsByTarget(),
          {(service: SnsService.x, handle: 'alice'): 1});
    });

    test('同じ時刻に並んでも新しい方を最新とみなす', () async {
      final older = await completedSnapshot('alice', 'followers', [user('1')],
          startedAt: 1000);
      final newer = await completedSnapshot('alice', 'followers', [user('2')],
          startedAt: 1000);

      expect((await db.latestCompleted(SnsService.x, 'alice', 'followers'))!.id, newer);
      expect((await db.listSnapshots(targetHandle: 'alice')).map((s) => s.id),
          [newer, older]);
    });

    test('totalExpected を入れると取得率が出る', () async {
      final id =
          await completedSnapshot('alice', 'followers', [user('1'), user('2')]);
      await db.setTotalExpected(id, 4);
      expect((await db.getSnapshot(id))!.completeness, 0.5);

      // null を渡したら何も書き換えない
      await db.setTotalExpected(id, null);
      expect((await db.getSnapshot(id))!.totalExpected, 4);
    });

    test('totalExpected が無ければ取得率は出ない', () async {
      final id = await completedSnapshot('alice', 'followers', [user('1')]);
      expect((await db.getSnapshot(id))!.completeness, isNull);
    });
  });

  // ───────────────────────── 相互判定 ─────────────────────────

  group('相互判定', () {
    late int followers;
    late int following;

    setUp(() async {
      // 1,2 は相互 / 3 はフォロワーのみ (片思われ) / 4,5 はフォローのみ (片思い)
      followers = await completedSnapshot(
          'alice', 'followers', [user('1'), user('2'), user('3')]);
      following = await completedSnapshot(
          'alice', 'following', [user('1'), user('2'), user('4'), user('5')]);
    });

    test('件数が合う', () async {
      final c = await db.relationCounts(
          followersSnapshotId: followers, followingSnapshotId: following);
      expect(c.mutual, 2);
      expect(c.onlyFollowers, 1);
      expect(c.onlyFollowing, 2);
    });

    test('中身が件数と一致する', () async {
      Future<List<String>> ids(String? onlyIn) async =>
          (await db.relationMembers(
            followersSnapshotId: followers,
            followingSnapshotId: following,
            onlyIn: onlyIn,
          ))
              .map((u) => u.restId)
              .toList()
            ..sort();

      expect(await ids(null), ['1', '2']);
      expect(await ids('followers'), ['3']);
      expect(await ids('following'), ['4', '5']);
    });

    test('ページングしても重複・取りこぼしが出ない', () async {
      final page1 = await db.relationMembers(
          followersSnapshotId: followers,
          followingSnapshotId: following,
          onlyIn: 'following',
          limit: 1,
          offset: 0);
      final page2 = await db.relationMembers(
          followersSnapshotId: followers,
          followingSnapshotId: following,
          onlyIn: 'following',
          limit: 1,
          offset: 1);
      expect({page1.single.restId, page2.single.restId}, {'4', '5'});
    });
  });

  // ───────────────────────── 世代間の差分 ─────────────────────────

  group('世代間の差分', () {
    late int older;
    late int newer;

    setUp(() async {
      older = await completedSnapshot(
          'alice',
          'followers',
          [user('1', statuses: 10), user('2', statuses: 20), user('3')],
          startedAt: 1000);
      newer = await completedSnapshot(
          'alice',
          'followers',
          [user('1', statuses: 10), user('2', statuses: 25), user('4')],
          startedAt: 2000);
    });

    test('増えた / 減った の件数が合う', () async {
      final c = await db.diffCounts(oldSnapshotId: older, newSnapshotId: newer);
      expect(c.added, 1); // 4
      expect(c.removed, 1); // 3
    });

    test('増えた / 減った の中身が合う', () async {
      final added = await db.diffMembers(
          oldSnapshotId: older, newSnapshotId: newer, added: true);
      final removed = await db.diffMembers(
          oldSnapshotId: older, newSnapshotId: newer, added: false);
      expect(added.map((u) => u.restId), ['4']);
      expect(removed.map((u) => u.restId), ['3']);
    });

    test('件数が動いた人だけを拾う', () async {
      final changes =
          await db.countChanges(oldSnapshotId: older, newSnapshotId: newer);
      expect(changes.map((c) => c.user.restId), ['2']);
      expect(changes.single.statusesDelta, 5);
    });

    test('一覧と総数の条件がずれない', () async {
      final total =
          await db.countChangesTotal(oldSnapshotId: older, newSnapshotId: newer);
      final all = await db.countChanges(
          oldSnapshotId: older, newSnapshotId: newer, limit: 1000);
      expect(total, all.length);
    });

    test('総数は一覧の上限に影響されない', () async {
      final a = await completedSnapshot('bob', 'followers',
          [for (var i = 0; i < 20; i++) user('$i', statuses: i)],
          startedAt: 1000);
      final b = await completedSnapshot('bob', 'followers',
          [for (var i = 0; i < 20; i++) user('$i', statuses: i + 1)],
          startedAt: 2000);

      expect(await db.countChangesTotal(oldSnapshotId: a, newSnapshotId: b), 20);
      expect(
          (await db.countChanges(oldSnapshotId: a, newSnapshotId: b, limit: 5))
              .length,
          5);
    });

    test('差分のページングが重複しない', () async {
      final a = await completedSnapshot('carol', 'followers', [user('0')],
          startedAt: 1000);
      final b = await completedSnapshot('carol', 'followers',
          [for (var i = 1; i <= 5; i++) user('$i', followers: i)],
          startedAt: 2000);

      final seen = <String>[];
      for (var offset = 0; offset < 5; offset += 2) {
        seen.addAll((await db.diffMembers(
                oldSnapshotId: a,
                newSnapshotId: b,
                added: true,
                limit: 2,
                offset: offset))
            .map((u) => u.restId));
      }
      expect(seen.toSet().length, 5);
    });
  });

  // ───────────────────── 世代をまたいだ相互の差分 ─────────────────────

  group('相互の差分', () {
    late int oldFollowers, oldFollowing, newFollowers, newFollowing;

    setUp(() async {
      // 旧: 相互 {1,2} / 片思われ {3} / 片思い {4}
      oldFollowers = await completedSnapshot(
          'alice', 'followers', [user('1'), user('2'), user('3')],
          startedAt: 1000);
      oldFollowing = await completedSnapshot(
          'alice', 'following', [user('1'), user('2'), user('4')],
          startedAt: 1000);
      // 新: 相互 {1,5} / 片思われ {3,7} / 片思い {6}
      newFollowers = await completedSnapshot('alice', 'followers',
          [user('1'), user('3'), user('5'), user('7')],
          startedAt: 2000);
      newFollowing = await completedSnapshot(
          'alice', 'following', [user('1'), user('5'), user('6')],
          startedAt: 2000);
    });

    Future<({int added, int removed})> counts(String? onlyIn) =>
        db.relationDiffCounts(
          oldFollowersId: oldFollowers,
          oldFollowingId: oldFollowing,
          newFollowersId: newFollowers,
          newFollowingId: newFollowing,
          onlyIn: onlyIn,
        );

    Future<List<String>> members(String? onlyIn, bool added) async =>
        (await db.relationDiffMembers(
          oldFollowersId: oldFollowers,
          oldFollowingId: oldFollowing,
          newFollowersId: newFollowers,
          newFollowingId: newFollowing,
          onlyIn: onlyIn,
          added: added,
        ))
            .map((u) => u.restId)
            .toList()
          ..sort();

    test('相互の増減', () async {
      final c = await counts(null);
      expect(c.added, 1); // 5
      expect(c.removed, 1); // 2
      expect(await members(null, true), ['5']);
      expect(await members(null, false), ['2']);
    });

    test('片思われの増減', () async {
      final c = await counts('followers');
      expect(c.added, 1); // 7
      expect(c.removed, 0);
      expect(await members('followers', true), ['7']);
      // 3 は両方の世代に居るので差分に出さない
      expect(await members('followers', false), isEmpty);
    });

    test('片思いの増減', () async {
      final c = await counts('following');
      expect(c.added, 1); // 6
      expect(c.removed, 1); // 4
      expect(await members('following', true), ['6']);
      expect(await members('following', false), ['4']);
    });

    test('件数と中身が一致する', () async {
      for (final onlyIn in [null, 'followers', 'following']) {
        final c = await counts(onlyIn);
        expect((await members(onlyIn, true)).length, c.added, reason: '$onlyIn');
        expect((await members(onlyIn, false)).length, c.removed,
            reason: '$onlyIn');
      }
    });

    test('同じ世代どうしなら差分は出ない', () async {
      final c = await db.relationDiffCounts(
        oldFollowersId: newFollowers,
        oldFollowingId: newFollowing,
        newFollowersId: newFollowers,
        newFollowingId: newFollowing,
      );
      expect(c.added, 0);
      expect(c.removed, 0);
    });

    test('差分にも絞り込みと並び替えが効く', () async {
      // 相互から抜けた人を増やして並びを見る
      final older = await completedSnapshot('bob', 'followers',
          [user('1', followers: 10), user('2', followers: 30, protected: true)],
          startedAt: 1000);
      // users は最新値で上書きされる。鍵の絞り込みは users を見るので、
      // 後から入る側でも鍵のままにしておく
      final olderG = await completedSnapshot(
          'bob', 'following', [user('1'), user('2', protected: true)],
          startedAt: 1000);
      final newer =
          await completedSnapshot('bob', 'followers', [], startedAt: 2000);
      final newerG =
          await completedSnapshot('bob', 'following', [], startedAt: 2000);

      Future<List<String>> removed({FollowFilter? filter, FollowSort? sort}) async =>
          (await db.relationDiffMembers(
            oldFollowersId: older,
            oldFollowingId: olderG,
            newFollowersId: newer,
            newFollowingId: newerG,
            added: false,
            filter: filter ?? FollowFilter.none,
            sort: sort ?? FollowSort.initial,
          ))
              .map((u) => u.restId)
              .toList();

      expect(await removed(), ['2', '1']);
      expect(
          await removed(
              sort: const FollowSort(FollowSortKey.followers,
                  descending: false)),
          ['1', '2']);
      expect(await removed(filter: const FollowFilter(protected: true)), ['2']);
    });
  });

  // ───────────────────────── 一覧の読み出し ─────────────────────────

  group('一覧の読み出し', () {
    late int snapshotId;

    setUp(() async {
      snapshotId = await completedSnapshot('alice', 'followers', [
        user('1', screenName: 'zebra', name: 'Zoe', followers: 300, friends: 100),
        user('2', screenName: 'apple', name: 'Ann', followers: 100, friends: 50),
        user('3', screenName: 'mango', name: 'Max', followers: 200, friends: 400),
      ]);
    });

    test('フォロワー数の降順', () async {
      expect((await db.members(snapshotId)).map((u) => u.restId),
          ['1', '3', '2']);
    });

    test('@ID 順は昇順と降順で反転する', () async {
      Future<List<String>> ids(bool desc) async => (await db.members(snapshotId,
              sort: FollowSort(FollowSortKey.screenName, descending: desc)))
          .map((u) => u.screenName)
          .toList();

      expect(await ids(false), ['apple', 'mango', 'zebra']);
      expect(await ids(true), ['zebra', 'mango', 'apple']);
    });

    test('F比', () async {
      // 3.0 / 2.0 / 0.5
      expect(
          (await db.members(snapshotId,
                  sort: const FollowSort(FollowSortKey.ratio)))
              .map((u) => u.restId),
          ['1', '2', '3']);
      expect(
          (await db.members(snapshotId,
                  sort: const FollowSort(FollowSortKey.ratio,
                      descending: false)))
              .map((u) => u.restId),
          ['3', '2', '1']);
    });

    test('フォロワー数は向きだけが変わる', () async {
      expect(
          (await db.members(snapshotId,
                  sort: const FollowSort(FollowSortKey.followers,
                      descending: false)))
              .map((u) => u.restId),
          ['2', '3', '1']);
    });

    test('検索は @ID と表示名の両方に当たる', () async {
      Future<List<String>> ids(String q) async =>
          (await db.members(snapshotId, filter: FollowFilter(search: q)))
              .map((u) => u.restId)
              .toList();

      expect(await ids('ang'), ['3']);
      expect(await ids('Ann'), ['2']);
      expect(await ids('いない'), isEmpty);
    });

    test('取れていない投稿数は向きにかかわらず末尾に置く', () async {
      final id = await completedSnapshot('carol', 'followers', [
        user('1', statuses: 10),
        user('2'), // 投稿数が取れていない
        user('3', statuses: 5),
      ]);

      Future<List<String>> ids(bool desc) async => (await db.members(id,
              sort: FollowSort(FollowSortKey.statuses, descending: desc)))
          .map((u) => u.restId)
          .toList();

      // 昇順で NULL が先頭に来ると「投稿 0 件」と見分けが付かない
      expect(await ids(true), ['1', '3', '2']);
      expect(await ids(false), ['3', '1', '2']);
    });

    test('ページングが安定している', () async {
      final all = await db.members(snapshotId, limit: 100);
      final paged = <String>[];
      for (var offset = 0; offset < 3; offset++) {
        paged.add((await db.members(snapshotId, limit: 1, offset: offset))
            .single
            .restId);
      }
      expect(paged, all.map((u) => u.restId).toList());
    });

    test('鍵アカウントで絞れる', () async {
      final id = await completedSnapshot('carol', 'followers', [
        user('1', protected: true),
        user('2'),
        user('3', protected: true),
      ]);

      Future<List<String>> ids(bool? protectedOnly) async => (await db.members(
              id, filter: FollowFilter(protected: protectedOnly)))
          .map((u) => u.restId)
          .toList()
        ..sort();

      expect(await ids(true), ['1', '3']);
      expect(await ids(false), ['2']);
      // 指定なしは素通し
      expect(await ids(null), ['1', '2', '3']);
    });

    test('認証済みで絞れる', () async {
      final id = await completedSnapshot('carol', 'followers', [
        user('1', verified: true),
        user('2'),
      ]);

      expect(
          (await db.members(id, filter: const FollowFilter(verified: true)))
              .map((u) => u.restId),
          ['1']);
      expect(
          (await db.members(id, filter: const FollowFilter(verified: false)))
              .map((u) => u.restId),
          ['2']);
    });

    test('絞り込みは重ねられる', () async {
      final id = await completedSnapshot('carol', 'followers', [
        user('1', screenName: 'alpha', protected: true, verified: true),
        user('2', screenName: 'alpine', protected: true),
        user('3', screenName: 'beta', verified: true),
      ]);

      final rows = await db.members(id,
          filter: const FollowFilter(
              search: 'alp', protected: true, verified: true));
      expect(rows.map((u) => u.restId), ['1']);
    });

    test('絞り込みが空なら何も落とさない', () {
      expect(const FollowFilter().isEmpty, isTrue);
      expect(const FollowFilter().clause.sql, '');
      expect(const FollowFilter(protected: false).isEmpty, isFalse);
      expect(const FollowFilter(protected: true, verified: true).activeCount, 2);
    });

    test('listSnapshots は種別で絞れる', () async {
      await completedSnapshot('alice', 'following', [user('9')]);
      expect((await db.listSnapshots(targetHandle: 'alice')).length, 2);
      expect(
          (await db.listSnapshots(targetHandle: 'alice', kind: 'following'))
              .length,
          1);
    });
  });

  // ───────────────────────── 間引き ─────────────────────────

  group('間引き', () {
    test('参照されなくなった users を消す', () async {
      final id = await completedSnapshot('alice', 'followers', [user('1')]);
      expect(await countRows('users'), 1);

      final raw = await db.debugDatabase();
      await raw
          .delete('snapshot_members', where: 'snapshotId = ?', whereArgs: [id]);
      expect(await db.pruneOrphanUsers(), 1);
      expect(await countRows('users'), 0);
    });

    test('間引くと members も道連れになる', () async {
      await useTempFile('follow_db_members');
      for (var i = 0; i < 3; i++) {
        await completedSnapshot('alice', 'followers', [user('$i')],
            startedAt: 1000 + i);
      }
      await db.pruneToSizeLimit(0, keepPerKind: 1);
      expect(await countRows('snapshot_members'), 1);
    });

    test('種別ごとに世代を数える', () async {
      await useTempFile('follow_db_kind');
      for (var i = 0; i < 3; i++) {
        await completedSnapshot('alice', 'followers', [user('$i')],
            startedAt: 1000 + i);
        await completedSnapshot('alice', 'following', [user('$i')],
            startedAt: 1000 + i);
      }
      // followers と following で 1 世代ずつ残る
      await db.pruneToSizeLimit(0, keepPerKind: 1);
      expect((await db.listSnapshots(targetHandle: 'alice')).length, 2);
    });

    test('未完了のスナップショットは間引かない', () async {
      await useTempFile('follow_db_running');
      for (var i = 0; i < 3; i++) {
        await completedSnapshot('alice', 'followers', [user('$i')],
            startedAt: 1000 + i);
      }
      final running =
          await db.startSnapshot(
          service: SnsService.x, targetHandle: 'alice', kind: 'followers');
      await db.addBatch(snapshotId: running, users: [user('9')], cursor: 'c');

      // 途中で消されると再開できなくなる
      await db.pruneToSizeLimit(0, keepPerKind: 1);
      expect(await db.getSnapshot(running), isNotNull);
    });

    test('サイズ上限を超えたら古い世代から消す', () async {
      await useTempFile('follow_db_size');

      final ids = <int>[];
      for (var i = 0; i < 5; i++) {
        ids.add(await completedSnapshot('alice', 'followers',
            [for (var n = 0; n < 50; n++) user('$i-$n')],
            startedAt: 1000 + i));
      }
      expect(await db.databaseSizeBytes(), greaterThan(0));

      // 上限 0 = 必ず超えている。keepPerKind を守って 3 世代だけ消える
      expect(await db.pruneToSizeLimit(0, keepPerKind: 2), 3);
      expect(
          (await db.listSnapshots(targetHandle: 'alice')).map((s) => s.id),
          [ids[4], ids[3]]);
    });

    test('上限に収まっていれば何もしない', () async {
      await useTempFile('follow_db_size2');

      for (var i = 0; i < 5; i++) {
        await completedSnapshot('alice', 'followers', [user('$i')],
            startedAt: 1000 + i);
      }
      expect(await db.pruneToSizeLimit(100 * 1024 * 1024), 0);
      expect((await db.listSnapshots(targetHandle: 'alice')).length, 5);
    });
  });

  // ───────────────────────── 使用量 ─────────────────────────

  group('使用量', () {
    test('対象ごとの行数を返す', () async {
      await completedSnapshot('alice', 'followers', [user('1'), user('2')]);
      await completedSnapshot('alice', 'following', [user('1')]);
      await completedSnapshot('bob', 'followers', [user('3')]);
      expect(await db.memberRowsByTarget(), {
        (service: SnsService.x, handle: 'alice'): 3,
        (service: SnsService.x, handle: 'bob'): 1,
      });
    });

    test('インメモリではファイルが無いので 0', () async {
      await db.listTargets();
      expect(await db.databaseSizeBytes(), 0);
    });
  });
}
