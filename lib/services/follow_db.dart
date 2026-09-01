import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/follow_user.dart';
import '../models/sns_service.dart';

/// フォロー/フォロワー走査の保存先。
///
/// 3 テーブル構成:
///   users            ユーザーのプロフィール。restId で一意。何度出ても 1 行
///   snapshots        1 回の走査 (対象 × 種別 × 実行日時)。cursor も持つので再開できる
///   snapshot_members スナップショットに含まれる restId の集合。差分はこの集合演算
///
/// users を分けているのは、同じユーザーが何世代にも現れても
/// プロフィールを 1 行に集約するため。members は (snapshotId, restId) だけの
/// 軽い行なので、世代を重ねても容量が線形に膨らみにくい。
class FollowDb {
  FollowDb._();
  static final instance = FollowDb._();

  static const _fileName = 'follow_capture.db';

  /// v2: 相互判定用に runs / snapshots.runId を追加し、
  ///     snapshot_members に「その時点の」件数を持たせて推移を取れるようにした
  /// v3: 走査対象を targets として明示。自分以外の任意 ID も対象にでき、
  ///     実行アカウントとスケジュールを対象ごとに持つ
  /// v4: 想定件数 (プロフィール上のフォロワー数/フォロー数) を記録し、
  ///     取りこぼしに気づけるようにした
  /// v5: handle の大文字小文字をならす。引くときは小文字化していたのに
  ///     書くときは素通しだったため、大文字で入った行が
  ///     スケジュール判定から漏れて毎回取り直しになっていた
  /// v6: Bluesky も対象にできるよう service を持たせる。
  ///     handle は X と Bluesky で衝突しうるので、対象のキーを
  ///     (service, handle) にした
  /// v7: ブロック調査。つながっている人のフォロー先をたどり、
  ///     実行アカウントとの関係 (blocked_by / blocking) を集める
  static const _version = 7;

  Database? _db;

  /// テストから SQLite の実装を差し替えるための口。
  ///
  /// sqflite は端末側のプラグインなのでテスト VM では動かない。
  /// FFI 版の factory をここに挿すと、本番と同じ [_createSchema] /
  /// マイグレーションを通したまま実際の SQLite を叩ける。
  @visibleForTesting
  DatabaseFactory? factoryOverride;

  /// 保存先の差し替え。テストはインメモリか一時ファイルを指す
  @visibleForTesting
  String? pathOverride;

  Future<String> _path() async =>
      pathOverride ?? p.join(await getDatabasesPath(), _fileName);

  /// 開いた DB を閉じる。テストのケース間で状態を持ち越さないために使う
  @visibleForTesting
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// 開いている接続そのもの。インメモリの DB は接続ごとに別物になるため、
  /// テストから中身を直接覗くにはこの接続を借りる必要がある
  @visibleForTesting
  Future<Database> debugDatabase() => _database;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await (factoryOverride ?? databaseFactory).openDatabase(
      await _path(),
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: (db, _) async {
          await _createSchema(db);
          await _upgradeToV2(db);
          await _upgradeToV3(db);
          await _upgradeToV4(db);
          await _upgradeToV6(db);
          await _upgradeToV7(db);
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) await _upgradeToV2(db);
          if (from < 3) await _upgradeToV3(db);
          if (from < 4) await _upgradeToV4(db);
          if (from < 5) await _upgradeToV5(db);
          if (from < 6) await _upgradeToV6(db);
          if (from < 7) await _upgradeToV7(db);
        },
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    return _db!;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE users (
        restId TEXT PRIMARY KEY,
        screenName TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        followersCount INTEGER NOT NULL DEFAULT 0,
        friendsCount INTEGER NOT NULL DEFAULT 0,
        statusesCount INTEGER,
        avatarUrl TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        verified INTEGER NOT NULL DEFAULT 0,
        isProtected INTEGER NOT NULL DEFAULT 0,
        location TEXT NOT NULL DEFAULT '',
        createdAt TEXT NOT NULL DEFAULT '',
        updatedAt INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_users_screenName ON users(screenName)');

    await db.execute('''
      CREATE TABLE snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        targetHandle TEXT NOT NULL,
        kind TEXT NOT NULL,
        sessionAccountId TEXT,
        startedAt INTEGER NOT NULL,
        completedAt INTEGER,
        status TEXT NOT NULL,
        reason TEXT,
        cursor TEXT,
        collectedCount INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_snapshots_target ON snapshots(targetHandle, kind, startedAt)');

    await db.execute('''
      CREATE TABLE snapshot_members (
        snapshotId INTEGER NOT NULL,
        restId TEXT NOT NULL,
        PRIMARY KEY (snapshotId, restId),
        FOREIGN KEY (snapshotId) REFERENCES snapshots(id) ON DELETE CASCADE
      )
    ''');
  }

  /// 相互判定と件数推移のための拡張。
  ///
  /// 相互は「同じ対象の followers と following を突き合わせる」必要があるので、
  /// 2 本の走査を 1 つの run にまとめる。
  /// 件数を snapshot_members にも持たせるのは、users が最新値で上書きされてしまい
  /// 「投稿数がいくつ増えたか」を後から出せないため。
  static Future<void> _upgradeToV2(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        targetHandle TEXT NOT NULL,
        startedAt INTEGER NOT NULL,
        completedAt INTEGER,
        status TEXT NOT NULL
      )
    ''');
    for (final sql in const [
      'ALTER TABLE snapshots ADD COLUMN runId INTEGER',
      'ALTER TABLE snapshot_members ADD COLUMN followersCount INTEGER',
      'ALTER TABLE snapshot_members ADD COLUMN friendsCount INTEGER',
      'ALTER TABLE snapshot_members ADD COLUMN statusesCount INTEGER',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {
        // 既にある場合は無視
      }
    }
  }

  /// 走査対象。自分のアカウントに限らず任意の ID を登録できる。
  ///
  /// 実行アカウントを対象ごとに持つのは、鍵垢の FF は「その鍵垢と
  /// つながっているアカウント」でないとページに一覧が出ないため。
  /// スケジュールは種別ごとに分ける（フォロワーは重く、フォローは軽い）。
  static Future<void> _upgradeToV3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS targets (
        handle TEXT PRIMARY KEY,
        displayName TEXT NOT NULL DEFAULT '',
        avatarUrl TEXT NOT NULL DEFAULT '',
        restId TEXT,
        sessionAccountId TEXT,
        followersIntervalDays INTEGER NOT NULL DEFAULT 0,
        followingIntervalDays INTEGER NOT NULL DEFAULT 0,
        addedAt INTEGER NOT NULL
      )
    ''');
    // 既存のスナップショットから対象を復元しておく
    await db.execute('''
      INSERT OR IGNORE INTO targets (handle, sessionAccountId, addedAt)
      SELECT LOWER(targetHandle), MAX(sessionAccountId), MIN(startedAt)
      FROM snapshots GROUP BY LOWER(targetHandle)
    ''');
  }

  /// 想定件数。取得完了時に「取りこぼしがないか」を照合するために持つ。
  static Future<void> _upgradeToV4(Database db) async {
    try {
      await db.execute('ALTER TABLE snapshots ADD COLUMN totalExpected INTEGER');
    } catch (_) {
      // 既にある場合は無視
    }
  }

  /// 既に入っている handle を小文字にそろえる。
  ///
  /// 読み出しは [_norm] を通していたが書き込みは素通しだったので、
  /// 大文字混じりで入った行は latestCompleted から見えず、
  /// 「毎回スケジュールの期日が来ている」状態になっていた。
  static Future<void> _upgradeToV5(Database db) async {
    await db.execute('UPDATE snapshots SET targetHandle = LOWER(targetHandle) '
        'WHERE targetHandle <> LOWER(targetHandle)');
    // handle は主キー。小文字の行が既にあるとぶつかるので、その場合は捨てる
    await db.execute('UPDATE OR IGNORE targets SET handle = LOWER(handle) '
        'WHERE handle <> LOWER(handle)');
    await db.execute('DELETE FROM targets WHERE handle <> LOWER(handle)');
  }

  /// v6 より前に入った行の SNS。当時は X しか扱えなかった
  static const _defaultService = 'x';

  /// 対象に SNS を持たせる。
  ///
  /// X の screen_name と Bluesky の handle は別空間なので、handle だけでは
  /// 対象を一意に指せない。targets の主キーを (service, handle) にする。
  /// SQLite は主キーを後から変えられないのでテーブルごと作り直す。
  static Future<void> _upgradeToV6(Database db) async {
    try {
      await db.execute('ALTER TABLE snapshots ADD COLUMN service TEXT '
          "NOT NULL DEFAULT '$_defaultService'");
    } catch (_) {
      // 既にある場合は無視
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS targets_v6 (
        handle TEXT NOT NULL,
        service TEXT NOT NULL DEFAULT '$_defaultService',
        displayName TEXT NOT NULL DEFAULT '',
        avatarUrl TEXT NOT NULL DEFAULT '',
        restId TEXT,
        sessionAccountId TEXT,
        followersIntervalDays INTEGER NOT NULL DEFAULT 0,
        followingIntervalDays INTEGER NOT NULL DEFAULT 0,
        addedAt INTEGER NOT NULL,
        PRIMARY KEY (service, handle)
      )
    ''');
    // v6 より前の対象はすべて X
    await db.execute('''
      INSERT OR IGNORE INTO targets_v6
        (handle, service, displayName, avatarUrl, restId, sessionAccountId,
         followersIntervalDays, followingIntervalDays, addedAt)
      SELECT handle, '$_defaultService', displayName, avatarUrl, restId,
         sessionAccountId, followersIntervalDays, followingIntervalDays, addedAt
      FROM targets
    ''');
    await db.execute('DROP TABLE targets');
    await db.execute('ALTER TABLE targets_v6 RENAME TO targets');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snapshots_service_target '
        'ON snapshots(service, targetHandle, kind, startedAt)');
  }

  /// ブロック調査。
  ///
  /// 起点 (誰かのフォロー/フォロワー/相互) の 1 人ずつについて、その人の
  /// フォロー一覧を取る。一覧の各ユーザーには実行アカウントから見た関係
  /// (relationship_perspectives) が載るので、走査したそばから
  /// ブロックの有無が分かる。
  ///
  ///   block_runs      調査 1 回。起点と進み具合を持つ
  ///   block_sources   起点の 1 人。どこまで進んだか (cursor) を持つので
  ///                   途中で切れてもその人の続きから再開できる
  ///   block_findings  見つかった関係。同じ人が複数の source から
  ///                   見つかるので (source, restId) を主キーにする
  static Future<void> _upgradeToV7(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS block_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        service TEXT NOT NULL,
        targetHandle TEXT NOT NULL,
        sessionAccountId TEXT,
        origin TEXT NOT NULL,
        startedAt INTEGER NOT NULL,
        completedAt INTEGER,
        status TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS block_sources (
        runId INTEGER NOT NULL,
        restId TEXT NOT NULL,
        screenName TEXT NOT NULL,
        friendsCount INTEGER,
        position INTEGER NOT NULL,
        status TEXT NOT NULL,
        cursor TEXT,
        collected INTEGER NOT NULL DEFAULT 0,
        reason TEXT,
        PRIMARY KEY (runId, restId)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_block_sources_run '
        'ON block_sources(runId, status, position)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS block_findings (
        runId INTEGER NOT NULL,
        sourceRestId TEXT NOT NULL,
        restId TEXT NOT NULL,
        blockedBy INTEGER,
        blocking INTEGER,
        muting INTEGER,
        PRIMARY KEY (runId, sourceRestId, restId)
      )
    ''');
    // 「誰から見つかったか」を横断で数えるため restId 側にも索引を張る
    await db.execute('CREATE INDEX IF NOT EXISTS idx_block_findings_user '
        'ON block_findings(runId, restId)');
  }

  Future<void> setTotalExpected(int snapshotId, int? total) async {
    if (total == null) return;
    final db = await _database;
    await db.update('snapshots', {'totalExpected': total},
        where: 'id = ?', whereArgs: [snapshotId]);
  }

  // ─── 走査対象 ───

  Future<List<FollowTarget>> listTargets() async {
    final db = await _database;
    final rows = await db.query('targets', orderBy: 'addedAt');
    return rows.map(FollowTarget.fromRow).toList();
  }

  Future<FollowTarget?> getTarget(SnsService service, String handle) async {
    final db = await _database;
    final rows = await db.query('targets',
        where: 'service = ? AND handle = ?',
        whereArgs: [service.name, _norm(handle)],
        limit: 1);
    return rows.isEmpty ? null : FollowTarget.fromRow(rows.first);
  }

  Future<void> upsertTarget(FollowTarget target) async {
    final db = await _database;
    // 引くときは小文字化するので、入れるときもそろえる
    final row = target.toRow()..['handle'] = _norm(target.handle);
    await db.insert('targets', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 対象と、そこに紐づくスナップショット一式を消す
  Future<void> deleteTarget(SnsService service, String handle) async {
    final db = await _database;
    final h = _norm(handle);
    final sv = service.name;
    await db.transaction((txn) async {
      await txn.delete('snapshot_members',
          where: 'snapshotId IN (SELECT id FROM snapshots '
              'WHERE service = ? AND targetHandle = ?)',
          whereArgs: [sv, h]);
      await txn.delete('snapshots',
          where: 'service = ? AND targetHandle = ?', whereArgs: [sv, h]);
      await txn.delete('targets',
          where: 'service = ? AND handle = ?', whereArgs: [sv, h]);
    });
    await pruneOrphanUsers();
    // VACUUM しないとファイルサイズが縮まず、削除しても使用量が減らないように見える
    try {
      await db.execute('VACUUM');
    } catch (e) {
      debugPrint('[FollowDb] VACUUM に失敗: $e');
    }
  }

  static String _norm(String handle) =>
      handle.replaceFirst('@', '').toLowerCase();

  /// 対象 × 種別の「最新の完了済み」スナップショット
  Future<FollowSnapshot?> latestCompleted(
      SnsService service, String handle, String kind) async {
    final db = await _database;
    final rows = await db.query('snapshots',
        where: "service = ? AND targetHandle = ? AND kind = ? "
            "AND status = 'completed'",
        whereArgs: [service.name, _norm(handle), kind],
        // 同じミリ秒に 2 本並んでも順序が決まるように id を第 2 キーに置く
        orderBy: 'startedAt DESC, id DESC',
        limit: 1);
    return rows.isEmpty ? null : FollowSnapshot.fromRow(rows.first);
  }

  /// 対象の未完了スナップショット（再開候補）。新しい順
  Future<List<FollowSnapshot>> resumableFor(
      SnsService service, String handle) async {
    final db = await _database;
    final rows = await db.query('snapshots',
        where: "service = ? AND targetHandle = ? "
            "AND status <> 'completed' AND cursor IS NOT NULL",
        whereArgs: [service.name, _norm(handle)],
        orderBy: 'startedAt DESC, id DESC');
    return rows.map(FollowSnapshot.fromRow).toList();
  }

  // ─── ストレージ使用量 ───

  /// DB ファイルの実サイズ。インメモリで開いている場合は 0
  Future<int> databaseSizeBytes() async {
    final path = await _path();
    if (path == inMemoryDatabasePath) return 0;
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : 0;
  }

  /// ブロック調査が占めている概算バイト数。
  ///
  /// SQLite の 1 ファイルなので実測はできない。行数から見積もる。
  /// 知りたいのは正確な値ではなく「フォロー/フォロワーの間引きを
  /// 発動させるべきか」なので、桁が合っていれば足りる。
  Future<int> blockScanBytes() async {
    final db = await _database;
    Future<int> count(String table) async =>
        Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
        0;

    // findings 1 行は 5 列の小さな行。users 側は調査でしか出てこない
    // 相手のぶんを見積もる (実測でおよそ 1 件 350 バイト前後)
    final findings = await count('block_findings');
    final onlyInScan = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM users WHERE restId NOT IN '
          '(SELECT restId FROM snapshot_members)',
        )) ??
        0;
    return findings * 60 + onlyInScan * 350;
  }

  /// フォロー/フォロワーが占めている概算。間引きの判定はこちらで行う
  Future<int> followDataBytes() async {
    final total = await databaseSizeBytes();
    final scan = await blockScanBytes();
    final rest = total - scan;
    return rest < 0 ? 0 : rest;
  }

  /// 対象ごとの snapshot_members 行数。使用量の按分に使う
  Future<Map<FollowTargetKey, int>> memberRowsByTarget() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT s.service AS sv, s.targetHandle AS h, COUNT(*) AS c '
      'FROM snapshot_members m JOIN snapshots s ON s.id = m.snapshotId '
      'GROUP BY s.service, s.targetHandle',
    );
    return {
      for (final r in rows)
        (service: _serviceOf(r['sv']), handle: r['h'] as String):
            (r['c'] as int?) ?? 0,
    };
  }

  /// 保持サイズの上限を超えていたら、古い完了スナップショットから削除する。
  /// 差分が取れなくなるので、(対象 × 種別) ごとに [keepPerKind] 世代は必ず残す。
  /// 上限を超えていたら、古い完了スナップショットから削除する。
  ///
  /// 判定にはブロック調査ぶんを含めない。調査は単体で GB に達するので、
  /// ファイル全体で測ると「スナップショットを全部消しても上限を
  /// 下回らない」状態になり、履歴が消し損になる。
  Future<int> pruneToSizeLimit(int limitBytes, {int keepPerKind = 2}) async {
    if (await followDataBytes() <= limitBytes) return 0;
    final db = await _database;

    final victims = await db.rawQuery('''
      SELECT id FROM (
        SELECT id, startedAt, ROW_NUMBER() OVER (
          PARTITION BY targetHandle, kind ORDER BY startedAt DESC, id DESC
        ) AS rn FROM snapshots WHERE status = 'completed'
      ) WHERE rn > ? ORDER BY startedAt ASC
    ''', [keepPerKind]);

    var deleted = 0;
    for (final row in victims) {
      final id = row['id'] as int;
      await db.delete('snapshot_members',
          where: 'snapshotId = ?', whereArgs: [id]);
      await db.delete('snapshots', where: 'id = ?', whereArgs: [id]);
      deleted++;
      // 消すたびに測ると重いので、数件ごとに確認する
      if (deleted % 5 == 0) {
        await db.execute('VACUUM');
        if (await followDataBytes() <= limitBytes) break;
      }
    }
    if (deleted > 0) {
      await pruneOrphanUsers();
      await db.execute('VACUUM');
    }
    return deleted;
  }

  // ─── 相互判定 ───
  //
  // followers と following を 1 つの run にまとめて記録していた時期があるが、
  // 「対象 × 種別の最新の完了済み」同士を突き合わせれば足りるので廃止した。
  // runs テーブルと snapshots.runId 列は、消すためだけに
  // マイグレーションを増やす価値が無いので残してある (書き込みはしない)。

  /// 相互・片思われ・片思いの件数
  Future<({int mutual, int onlyFollowers, int onlyFollowing})> relationCounts({
    required int followersSnapshotId,
    required int followingSnapshotId,
  }) async {
    final f = followersSnapshotId, g = followingSnapshotId;
    final db = await _database;
    Future<int> count(String sql, List<Object?> args) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql, args)) ?? 0;

    const inOther =
        'SELECT COUNT(*) FROM snapshot_members WHERE snapshotId = ? AND restId IN '
        '(SELECT restId FROM snapshot_members WHERE snapshotId = ?)';
    const notInOther =
        'SELECT COUNT(*) FROM snapshot_members WHERE snapshotId = ? AND restId NOT IN '
        '(SELECT restId FROM snapshot_members WHERE snapshotId = ?)';

    return (
      mutual: await count(inOther, [f, g]),
      onlyFollowers: await count(notInOther, [f, g]),
      onlyFollowing: await count(notInOther, [g, f]),
    );
  }

  // ─── スナップショット ───

  /// 走査を開始して snapshot 行を作る
  Future<int> startSnapshot({
    required SnsService service,
    required String targetHandle,
    required String kind,
    String? sessionAccountId,
  }) async {
    final db = await _database;
    return db.insert('snapshots', {
      'service': service.name,
      'targetHandle': _norm(targetHandle),
      'kind': kind,
      'sessionAccountId': sessionAccountId,
      'startedAt': DateTime.now().millisecondsSinceEpoch,
      'status': 'running',
      'collectedCount': 0,
    });
  }

  /// 1 ページ分を保存する。users は上書き、members は追加
  Future<void> addBatch({
    required int snapshotId,
    required List<FollowUser> users,
    String? cursor,
  }) async {
    if (users.isEmpty && cursor == null) return;
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final u in users) {
        batch.insert('users', _userRow(u, now),
            conflictAlgorithm: ConflictAlgorithm.replace);
        // 件数は「この走査時点の値」として members 側にも残す。
        // users は最新値で上書きされるため、推移はここからしか取れない。
        batch.insert(
          'snapshot_members',
          {
            'snapshotId': snapshotId,
            'restId': u.restId,
            'followersCount': u.followersCount,
            'friendsCount': u.friendsCount,
            'statusesCount': u.statusesCount,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);

      // cursor と件数を進める (中断してもここから再開できる)
      await txn.rawUpdate(
        'UPDATE snapshots SET cursor = ?, collectedCount = '
        '(SELECT COUNT(*) FROM snapshot_members WHERE snapshotId = ?) '
        'WHERE id = ?',
        [cursor, snapshotId, snapshotId],
      );
    });
  }

  Future<void> finishSnapshot({
    required int snapshotId,
    required bool completed,
    required String reason,
    String? cursor,
  }) async {
    final db = await _database;
    await db.update(
      'snapshots',
      {
        'status': completed ? 'completed' : 'interrupted',
        'reason': reason,
        'cursor': cursor,
        'completedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [snapshotId],
    );
  }

  Future<List<FollowSnapshot>> listSnapshots({
    SnsService? service,
    String? targetHandle,
    String? kind,
    int limit = 100,
  }) async {
    final db = await _database;
    final where = <String>[];
    final args = <Object?>[];
    if (service != null) {
      where.add('service = ?');
      args.add(service.name);
    }
    if (targetHandle != null) {
      where.add('targetHandle = ?');
      args.add(_norm(targetHandle));
    }
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    final rows = await db.query(
      'snapshots',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'startedAt DESC, id DESC',
      limit: limit,
    );
    return rows.map(FollowSnapshot.fromRow).toList();
  }

  Future<FollowSnapshot?> getSnapshot(int id) async {
    final db = await _database;
    final rows =
        await db.query('snapshots', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : FollowSnapshot.fromRow(rows.first);
  }

  // ─── メンバー ───

  /// スナップショットの中身を users と結合して返す。
  /// 数千件になるので必ずページングして読むこと。
  Future<List<FollowUser>> members(
    int snapshotId, {
    FollowFilter filter = FollowFilter.none,
    FollowSort sort = FollowSort.initial,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await _database;
    final f = filter.clause;
    final rows = await db.rawQuery(
      'SELECT $_snapshotColumns '
      'FROM snapshot_members m JOIN users u ON u.restId = m.restId '
      'WHERE m.snapshotId = ?${f.sql} '
      'ORDER BY ${sort.sql}, u.restId '
      'LIMIT ? OFFSET ?',
      [snapshotId, ...f.args, limit, offset],
    );
    return rows.map(_userFromSnapshotRow).toList();
  }

  /// 一覧に必要な列。件数は走査時点の値を優先し、無ければ最新値で代用する
  static const _snapshotColumns = 'u.*, '
      'COALESCE(m.followersCount, u.followersCount) AS snapFollowers, '
      'COALESCE(m.friendsCount, u.friendsCount) AS snapFriends, '
      'COALESCE(m.statusesCount, u.statusesCount) AS snapStatuses';

  /// 相互 (followers ∩ following)。[onlyIn] を指定すると片側だけを返す
  ///   null      → 相互
  ///   'followers' → フォロワーだがフォローしていない (片思われ)
  ///   'following' → フォローしているがフォロワーではない (片思い)
  Future<List<FollowUser>> relationMembers({
    required int followersSnapshotId,
    required int followingSnapshotId,
    String? onlyIn,
    FollowFilter filter = FollowFilter.none,
    FollowSort sort = FollowSort.initial,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await _database;
    final parts =
        _relationParts(followersSnapshotId, followingSnapshotId, onlyIn);
    final f = filter.clause;

    final rows = await db.rawQuery(
      'SELECT $_snapshotColumns '
      'FROM snapshot_members m JOIN users u ON u.restId = m.restId '
      'WHERE m.snapshotId = ? AND ${parts.secondaryClause}${f.sql} '
      'ORDER BY ${sort.sql}, u.restId LIMIT ? OFFSET ?',
      [parts.primary, parts.secondary, ...f.args, limit, offset],
    );
    return rows.map(_userFromSnapshotRow).toList();
  }

  /// 相互 / 片思われ / 片思い を「主にする側」と「突き合わせる側」に分解する。
  ///
  ///   相互      … フォロワーに居て、かつフォローにも居る
  ///   片思われ  … フォロワーに居て、フォローには居ない
  ///   片思い    … フォローに居て、フォロワーには居ない
  ///
  /// どれも「[primary] のメンバーであること」+「[secondary] に居る / 居ない」で
  /// 表せるので、1 か所にまとめて差分側と共有する。
  static ({int primary, int secondary, String secondaryClause}) _relationParts(
    int followersId,
    int followingId,
    String? onlyIn,
  ) {
    const inOther =
        'm.restId IN (SELECT restId FROM snapshot_members WHERE snapshotId = ?)';
    const notInOther =
        'm.restId NOT IN (SELECT restId FROM snapshot_members WHERE snapshotId = ?)';
    return switch (onlyIn) {
      'following' =>
        (primary: followingId, secondary: followersId, secondaryClause: notInOther),
      'followers' =>
        (primary: followersId, secondary: followingId, secondaryClause: notInOther),
      _ => (primary: followersId, secondary: followingId, secondaryClause: inOther),
    };
  }

  /// 両方に居るユーザーの件数の変化 (投稿数・フォロワー数の推移)。
  ///
  /// 3 万人規模の対象では変化した人だけでも数万件になる。
  /// 上限で打ち切ると「見えていない分がある」ことに気づけないので、
  /// 件数は [countChangesTotal] で別に数え、中身はページングで読む。
  ///
  /// 並びは ABS(投稿数の増減) の降順。offset でページを進めても順序が
  /// 崩れないよう restId を第 2 キーに入れてある。
  Future<List<FollowCountChange>> countChanges({
    required int oldSnapshotId,
    required int newSnapshotId,
    FollowFilter filter = FollowFilter.none,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await _database;
    final f = filter.clause;
    final rows = await db.rawQuery(
      'SELECT u.*, '
      'n.followersCount AS newFollowers, o.followersCount AS oldFollowers, '
      'n.statusesCount AS newStatuses, o.statusesCount AS oldStatuses '
      'FROM snapshot_members n '
      'JOIN snapshot_members o ON o.restId = n.restId AND o.snapshotId = ? '
      'JOIN users u ON u.restId = n.restId '
      'WHERE n.snapshotId = ? AND $_countChangedClause${f.sql} '
      // この画面の主役は「どれだけ動いたか」なので、並びは固定でよい
      'ORDER BY ABS(COALESCE(n.statusesCount,0) - COALESCE(o.statusesCount,0)) DESC, '
      'n.restId '
      'LIMIT ? OFFSET ?',
      [oldSnapshotId, newSnapshotId, ...f.args, limit, offset],
    );
    return rows
        .map((r) => FollowCountChange(
              user: _userFromRow(r),
              oldFollowers: r['oldFollowers'] as int?,
              newFollowers: r['newFollowers'] as int?,
              oldStatuses: r['oldStatuses'] as int?,
              newStatuses: r['newStatuses'] as int?,
            ))
        .toList();
  }

  /// 件数が変化したユーザーの総数
  Future<int> countChangesTotal({
    required int oldSnapshotId,
    required int newSnapshotId,
    FollowFilter filter = FollowFilter.none,
  }) async {
    final db = await _database;
    final f = filter.clause;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM snapshot_members n '
          'JOIN snapshot_members o ON o.restId = n.restId AND o.snapshotId = ? '
          'JOIN users u ON u.restId = n.restId '
          'WHERE n.snapshotId = ? AND $_countChangedClause${f.sql}',
          [oldSnapshotId, newSnapshotId, ...f.args],
        )) ??
        0;
  }

  /// 「投稿数かフォロワー数のどちらかが動いた」条件。
  /// 一覧と件数で条件がずれないよう 1 箇所にまとめる
  static const _countChangedClause =
      '(COALESCE(n.statusesCount,0) <> COALESCE(o.statusesCount,0) '
      ' OR COALESCE(n.followersCount,0) <> COALESCE(o.followersCount,0))';

  /// members / runMembers 用。走査時点の件数で上書きした FollowUser を返す
  static FollowUser _userFromSnapshotRow(Map<String, Object?> r) {
    final base = _userFromRow(r);
    return FollowUser(
      restId: base.restId,
      screenName: base.screenName,
      name: base.name,
      followersCount: (r['snapFollowers'] as int?) ?? base.followersCount,
      friendsCount: (r['snapFriends'] as int?) ?? base.friendsCount,
      statusesCount: (r['snapStatuses'] as int?) ?? base.statusesCount,
      avatarUrl: base.avatarUrl,
      description: base.description,
      verified: base.verified,
      isProtected: base.isProtected,
      location: base.location,
      createdAt: base.createdAt,
    );
  }

  /// 2 つのスナップショットの差分の件数。
  /// added = new にだけ居る / removed = old にだけ居る
  Future<({int added, int removed})> diffCounts({
    required int oldSnapshotId,
    required int newSnapshotId,
  }) async {
    final db = await _database;
    Future<int> onlyIn(int a, int b) async =>
        Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM snapshot_members WHERE snapshotId = ? '
          'AND restId NOT IN (SELECT restId FROM snapshot_members WHERE snapshotId = ?)',
          [a, b],
        )) ??
        0;
    return (
      added: await onlyIn(newSnapshotId, oldSnapshotId),
      removed: await onlyIn(oldSnapshotId, newSnapshotId),
    );
  }

  /// 片側にだけ居るユーザー。[added] が true なら new 側だけ、false なら old 側だけ。
  /// 全取得と入れ替わりの大きい比較では数万件になるのでページングして読むこと。
  Future<List<FollowUser>> diffMembers({
    required int oldSnapshotId,
    required int newSnapshotId,
    required bool added,
    FollowFilter filter = FollowFilter.none,
    FollowSort sort = FollowSort.initial,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await _database;
    final (base, other) = added
        ? (newSnapshotId, oldSnapshotId)
        : (oldSnapshotId, newSnapshotId);
    final f = filter.clause;
    final rows = await db.rawQuery(
      'SELECT $_snapshotColumns '
      'FROM snapshot_members m JOIN users u ON u.restId = m.restId '
      'WHERE m.snapshotId = ? AND m.restId NOT IN '
      '(SELECT restId FROM snapshot_members WHERE snapshotId = ?)${f.sql} '
      'ORDER BY ${sort.sql}, u.restId LIMIT ? OFFSET ?',
      [base, other, ...f.args, limit, offset],
    );
    return rows.map(_userFromSnapshotRow).toList();
  }

  // ─── 世代をまたいだ相互の差分 ───
  //
  // 相互はスナップショットとして保存していない (その都度 2 本を突き合わせて
  // 出している) ので、比べるには (フォロワー, フォロー) の組を 2 世代ぶん
  // 受け取って、その場で両方の集合を作って差を取る。

  /// 相互 / 片思われ / 片思い が、世代をまたいで何人増えて何人減ったか
  Future<({int added, int removed})> relationDiffCounts({
    required int oldFollowersId,
    required int oldFollowingId,
    required int newFollowersId,
    required int newFollowingId,
    String? onlyIn,
  }) async {
    final db = await _database;

    Future<int> count(bool added) async {
      final w = _relationDiffWhere(
        oldFollowersId: oldFollowersId,
        oldFollowingId: oldFollowingId,
        newFollowersId: newFollowersId,
        newFollowingId: newFollowingId,
        onlyIn: onlyIn,
        added: added,
      );
      return Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM snapshot_members m WHERE ${w.where}',
            w.args,
          )) ??
          0;
    }

    return (added: await count(true), removed: await count(false));
  }

  /// 相互 / 片思われ / 片思い の差分の中身
  Future<List<FollowUser>> relationDiffMembers({
    required int oldFollowersId,
    required int oldFollowingId,
    required int newFollowersId,
    required int newFollowingId,
    required bool added,
    String? onlyIn,
    FollowFilter filter = FollowFilter.none,
    FollowSort sort = FollowSort.initial,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await _database;
    final w = _relationDiffWhere(
      oldFollowersId: oldFollowersId,
      oldFollowingId: oldFollowingId,
      newFollowersId: newFollowersId,
      newFollowingId: newFollowingId,
      onlyIn: onlyIn,
      added: added,
    );
    final f = filter.clause;
    final rows = await db.rawQuery(
      'SELECT $_snapshotColumns '
      'FROM snapshot_members m JOIN users u ON u.restId = m.restId '
      'WHERE ${w.where}${f.sql} '
      'ORDER BY ${sort.sql}, u.restId LIMIT ? OFFSET ?',
      [...w.args, ...f.args, limit, offset],
    );
    return rows.map(_userFromSnapshotRow).toList();
  }

  /// 「新しい世代の集合に居て、古い世代の集合には居ない」を組み立てる。
  /// [added] が false なら新旧を入れ替えるだけ。
  static ({String where, List<Object?> args}) _relationDiffWhere({
    required int oldFollowersId,
    required int oldFollowingId,
    required int newFollowersId,
    required int newFollowingId,
    required String? onlyIn,
    required bool added,
  }) {
    final newer = _relationParts(newFollowersId, newFollowingId, onlyIn);
    final older = _relationParts(oldFollowersId, oldFollowingId, onlyIn);
    final (base, other) = added ? (newer, older) : (older, newer);

    return (
      where: 'm.snapshotId = ? AND ${base.secondaryClause} '
          'AND NOT (m.restId IN '
          '(SELECT restId FROM snapshot_members WHERE snapshotId = ?) '
          'AND ${other.secondaryClause})',
      args: [base.primary, base.secondary, other.primary, other.secondary],
    );
  }

  // ─── ブロック調査 ───

  /// フォロー数がこれを超える相手は走査しない。
  /// 1 人で数時間かかり、調査全体が進まなくなるため
  static const blockScanFriendLimit = 10000;

  /// 調査を始める。起点の一覧から走査対象を作る。
  ///
  /// [sources] は起点の並び順どおりに渡すこと。上から 1 人ずつ処理する。
  Future<int> startBlockRun({
    required SnsService service,
    required String targetHandle,
    required String origin,
    String? sessionAccountId,
    required List<FollowUser> sources,
  }) async {
    final db = await _database;
    final runId = await db.insert('block_runs', {
      'service': service.name,
      'targetHandle': _norm(targetHandle),
      'sessionAccountId': sessionAccountId,
      'origin': origin,
      'startedAt': DateTime.now().millisecondsSinceEpoch,
      'status': 'running',
    });

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < sources.length; i++) {
        final u = sources[i];
        // フォロー数が分かっていて多すぎる相手は、始める前に外しておく。
        // 分からない相手は走らせてみて、上限に達したら打ち切る
        final skip = u.friendsCount > blockScanFriendLimit;
        batch.insert('block_sources', {
          'runId': runId,
          'restId': u.restId,
          'screenName': u.screenName,
          'friendsCount': u.friendsCount,
          'position': i,
          'status': skip ? 'skipped' : 'pending',
          'reason': skip ? 'フォローが多すぎる (${u.friendsCount})' : null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    });
    return runId;
  }

  /// 次に処理する 1 人。中断した人が居ればその人を優先して続きから
  Future<BlockSource?> nextBlockSource(int runId) async {
    final db = await _database;
    final rows = await db.query('block_sources',
        where: "runId = ? AND status IN ('running', 'pending')",
        whereArgs: [runId],
        // running (中断した人) を先に。あとは起点の並び順
        orderBy: "CASE status WHEN 'running' THEN 0 ELSE 1 END, position",
        limit: 1);
    return rows.isEmpty ? null : BlockSource.fromRow(rows.first);
  }

  Future<void> markBlockSourceRunning(int runId, String restId) async {
    final db = await _database;
    await db.update('block_sources', {'status': 'running'},
        where: 'runId = ? AND restId = ?', whereArgs: [runId, restId]);
  }

  /// 1 ページぶんの結果を足す。cursor も一緒に進めるので、
  /// ここで落ちてもこの人の続きから再開できる
  Future<void> addBlockFindings({
    required int runId,
    required String sourceRestId,
    required List<FollowUser> users,
    String? cursor,
  }) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final u in users) {
        // 関係が 1 つも取れていない相手は記録しない。
        // 「調べた結果いずれでもない」と「そもそも取れていない」を
        // 混ぜると集計が濁る
        if (u.blockedBy == null && u.blocking == null && u.muting == null) {
          continue;
        }
        // 名前やアイコンは users から引くので、ここで入れておく。
        // 入れないと結果の一覧が JOIN で空になる。
        //
        // ただし調査は数千人 × 数百人を巡るので、全員ぶんの自己紹介文と
        // 場所まで持つとファイルが GB 級に膨らむ。結果の一覧に要るのは
        // @ID・名前・アイコン・件数なので、かさばる 2 つは捨てる。
        // 既にフォロー/フォロワーで保存済みの相手は、そちらの値を消さない
        batch.rawInsert(
          'INSERT INTO users '
          '(restId, screenName, name, followersCount, friendsCount, '
          ' statusesCount, avatarUrl, description, verified, isProtected, '
          ' location, createdAt, updatedAt) '
          "VALUES (?,?,?,?,?,?,?,'',?,?,'',?,?) "
          'ON CONFLICT(restId) DO UPDATE SET '
          '  screenName = excluded.screenName, '
          '  name = excluded.name, '
          '  followersCount = excluded.followersCount, '
          '  friendsCount = excluded.friendsCount, '
          '  statusesCount = excluded.statusesCount, '
          '  avatarUrl = excluded.avatarUrl, '
          '  verified = excluded.verified, '
          '  isProtected = excluded.isProtected, '
          '  updatedAt = excluded.updatedAt',
          [
            u.restId,
            u.screenName,
            u.name,
            u.followersCount,
            u.friendsCount,
            u.statusesCount,
            u.avatarUrl,
            u.verified ? 1 : 0,
            u.isProtected ? 1 : 0,
            u.createdAt,
            now,
          ],
        );
        batch.insert(
          'block_findings',
          {
            'runId': runId,
            'sourceRestId': sourceRestId,
            'restId': u.restId,
            'blockedBy': _boolInt(u.blockedBy),
            'blocking': _boolInt(u.blocking),
            'muting': _boolInt(u.muting),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await txn.rawUpdate(
        'UPDATE block_sources SET cursor = ?, collected = collected + ? '
        'WHERE runId = ? AND restId = ?',
        [cursor, users.length, runId, sourceRestId],
      );
    });
  }

  static int? _boolInt(bool? v) => v == null ? null : (v ? 1 : 0);

  static Map<String, Object?> _userRow(FollowUser u, int now) => {
        'restId': u.restId,
        'screenName': u.screenName,
        'name': u.name,
        'followersCount': u.followersCount,
        'friendsCount': u.friendsCount,
        'statusesCount': u.statusesCount,
        'avatarUrl': u.avatarUrl,
        'description': u.description,
        'verified': u.verified ? 1 : 0,
        'isProtected': u.isProtected ? 1 : 0,
        'location': u.location,
        'createdAt': u.createdAt,
        'updatedAt': now,
      };

  Future<void> finishBlockSource(int runId, String restId,
      {required String status, String? reason}) async {
    final db = await _database;
    await db.update(
        'block_sources', {'status': status, 'reason': reason, 'cursor': null},
        where: 'runId = ? AND restId = ?', whereArgs: [runId, restId]);
  }

  Future<void> finishBlockRun(int runId, {required bool completed}) async {
    final db = await _database;
    await db.update(
        'block_runs',
        {
          'status': completed ? 'completed' : 'interrupted',
          'completedAt': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [runId]);
  }

  Future<List<BlockRun>> listBlockRuns(
      {SnsService? service, String? targetHandle, int limit = 50}) async {
    final db = await _database;
    final where = <String>[];
    final args = <Object?>[];
    if (service != null) {
      where.add('service = ?');
      args.add(service.name);
    }
    if (targetHandle != null) {
      where.add('targetHandle = ?');
      args.add(_norm(targetHandle));
    }
    final rows = await db.query('block_runs',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'startedAt DESC, id DESC',
        limit: limit);
    return rows.map(BlockRun.fromRow).toList();
  }

  /// 途中でも見られるように、いつでも数えられるようにしておく
  Future<BlockRunProgress> blockRunProgress(int runId) async {
    final db = await _database;
    Future<int> count(String sql, [List<Object?> args = const []]) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql, [runId, ...args])) ?? 0;

    return BlockRunProgress(
      totalSources: await count('SELECT COUNT(*) FROM block_sources WHERE runId = ?'),
      doneSources: await count(
          "SELECT COUNT(*) FROM block_sources WHERE runId = ? AND status IN ('done', 'skipped', 'failed')"),
      skippedSources: await count(
          "SELECT COUNT(*) FROM block_sources WHERE runId = ? AND status = 'skipped'"),
      scanned: await count('SELECT COUNT(*) FROM block_findings WHERE runId = ?'),
      blockedBy: await count(
          'SELECT COUNT(DISTINCT restId) FROM block_findings WHERE runId = ? AND blockedBy = 1'),
      blocking: await count(
          'SELECT COUNT(DISTINCT restId) FROM block_findings WHERE runId = ? AND blocking = 1'),
      muting: await count(
          'SELECT COUNT(DISTINCT restId) FROM block_findings WHERE runId = ? AND muting = 1'),
    );
  }

  /// 見つかった相手を、発見元の人数つきで返す。
  /// [relation] は 'blockedBy' / 'blocking' / 'muting'
  Future<List<BlockFinding>> blockFindings({
    required int runId,
    required String relation,
    FollowFilter filter = FollowFilter.none,
    int limit = 100,
    int offset = 0,
  }) async {
    assert(const ['blockedBy', 'blocking', 'muting'].contains(relation));
    final db = await _database;
    final f = filter.clause;
    final rows = await db.rawQuery(
      'SELECT u.*, '
      'u.followersCount AS snapFollowers, u.friendsCount AS snapFriends, '
      'u.statusesCount AS snapStatuses, '
      'COUNT(*) AS sourceCount, '
      "GROUP_CONCAT(s.screenName, ', ') AS sourceNames "
      'FROM block_findings b '
      'JOIN users u ON u.restId = b.restId '
      'LEFT JOIN block_sources s '
      '  ON s.runId = b.runId AND s.restId = b.sourceRestId '
      'WHERE b.runId = ? AND b.$relation = 1${f.sql} '
      'GROUP BY b.restId '
      'ORDER BY sourceCount DESC, u.followersCount DESC, u.restId '
      'LIMIT ? OFFSET ?',
      [runId, ...f.args, limit, offset],
    );
    return rows
        .map((r) => BlockFinding(
              user: _userFromSnapshotRow(r),
              sourceCount: (r['sourceCount'] as int?) ?? 0,
              sourceNames: (r['sourceNames'] as String?) ?? '',
            ))
        .toList();
  }

  /// つながっている人たちの間で、何人からフォローされているか。
  /// 走査結果の集計だけで出せるので追加の通信は要らない
  Future<List<BlockFinding>> popularAmongSources({
    required int runId,
    bool onlyNotFollowed = false,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await _database;
    // 起点の一覧に居る相手 = 自分がフォローしている相手とみなす
    const notFollowed = ' AND b.restId NOT IN '
        '(SELECT restId FROM block_sources WHERE runId = b.runId)';
    final rows = await db.rawQuery(
      'SELECT u.*, '
      'u.followersCount AS snapFollowers, u.friendsCount AS snapFriends, '
      'u.statusesCount AS snapStatuses, '
      'COUNT(*) AS sourceCount, '
      "GROUP_CONCAT(s.screenName, ', ') AS sourceNames "
      'FROM block_findings b '
      'JOIN users u ON u.restId = b.restId '
      'LEFT JOIN block_sources s '
      '  ON s.runId = b.runId AND s.restId = b.sourceRestId '
      'WHERE b.runId = ?${onlyNotFollowed ? notFollowed : ''} '
      'GROUP BY b.restId '
      'ORDER BY sourceCount DESC, u.followersCount DESC, u.restId '
      'LIMIT ? OFFSET ?',
      [runId, limit, offset],
    );
    return rows
        .map((r) => BlockFinding(
              user: _userFromSnapshotRow(r),
              sourceCount: (r['sourceCount'] as int?) ?? 0,
              sourceNames: (r['sourceNames'] as String?) ?? '',
            ))
        .toList();
  }

  /// 参照されなくなった users を掃除する。
  ///
  /// ブロック調査の結果からも参照されているので、そちらも見る。
  /// 見ないと、数時間かけて集めた相手の名前やアイコンが消える
  Future<int> pruneOrphanUsers() async {
    final db = await _database;
    return db.rawDelete('DELETE FROM users WHERE restId NOT IN '
        '(SELECT restId FROM snapshot_members) '
        'AND restId NOT IN (SELECT restId FROM block_findings)');
  }

  static FollowUser _userFromRow(Map<String, Object?> r) => FollowUser(
        restId: r['restId'] as String,
        screenName: r['screenName'] as String,
        name: (r['name'] as String?) ?? '',
        followersCount: (r['followersCount'] as int?) ?? 0,
        friendsCount: (r['friendsCount'] as int?) ?? 0,
        statusesCount: r['statusesCount'] as int?,
        avatarUrl: (r['avatarUrl'] as String?) ?? '',
        description: (r['description'] as String?) ?? '',
        verified: (r['verified'] as int?) == 1,
        isProtected: (r['isProtected'] as int?) == 1,
        location: (r['location'] as String?) ?? '',
        createdAt: (r['createdAt'] as String?) ?? '',
      );
}

/// 対象を一意に指すキー。handle は SNS ごとに別空間なので service と対にする
typedef FollowTargetKey = ({SnsService service, String handle});

SnsService _serviceOf(Object? value) => SnsService.values.firstWhere(
      (s) => s.name == value,
      // v6 より前の行には service が無い。当時は X しか扱えなかった
      orElse: () => SnsService.x,
    );

/// 走査対象。自分のアカウントとは限らない
class FollowTarget {
  const FollowTarget({
    required this.service,
    required this.handle,
    required this.addedAt,
    this.displayName = '',
    this.avatarUrl = '',
    this.restId,
    this.sessionAccountId,
    this.followersIntervalDays = 0,
    this.followingIntervalDays = 0,
  });

  /// どの SNS の対象か
  final SnsService service;

  /// @ を除いた screen_name / handle（小文字）
  final String handle;
  final String displayName;
  final String avatarUrl;
  final String? restId;

  /// 走査に使うログイン済みアカウント。鍵垢はつながっているアカウントが要る
  final String? sessionAccountId;

  /// 0 ならスケジュールなし
  final int followersIntervalDays;
  final int followingIntervalDays;
  final DateTime addedAt;

  int intervalFor(String kind) =>
      kind == 'followers' ? followersIntervalDays : followingIntervalDays;

  FollowTargetKey get key => (service: service, handle: handle);

  FollowTarget copyWith({
    String? displayName,
    String? avatarUrl,
    String? restId,
    String? sessionAccountId,
    int? followersIntervalDays,
    int? followingIntervalDays,
  }) =>
      FollowTarget(
        service: service,
        handle: handle,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        restId: restId ?? this.restId,
        sessionAccountId: sessionAccountId ?? this.sessionAccountId,
        followersIntervalDays:
            followersIntervalDays ?? this.followersIntervalDays,
        followingIntervalDays:
            followingIntervalDays ?? this.followingIntervalDays,
        addedAt: addedAt,
      );

  Map<String, Object?> toRow() => {
        'service': service.name,
        'handle': handle,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'restId': restId,
        'sessionAccountId': sessionAccountId,
        'followersIntervalDays': followersIntervalDays,
        'followingIntervalDays': followingIntervalDays,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  factory FollowTarget.fromRow(Map<String, Object?> r) => FollowTarget(
        service: _serviceOf(r['service']),
        handle: r['handle'] as String,
        displayName: (r['displayName'] as String?) ?? '',
        avatarUrl: (r['avatarUrl'] as String?) ?? '',
        restId: r['restId'] as String?,
        sessionAccountId: r['sessionAccountId'] as String?,
        followersIntervalDays: (r['followersIntervalDays'] as int?) ?? 0,
        followingIntervalDays: (r['followingIntervalDays'] as int?) ?? 0,
        addedAt:
            DateTime.fromMillisecondsSinceEpoch((r['addedAt'] as int?) ?? 0),
      );
}

/// 並び替えの基準。向きは [FollowSort] が別に持つ。
///
/// 件数は「走査時点の値」を優先し、無ければ users の最新値で代用する。
enum FollowSortKey {
  followers('フォロワー数', 'COALESCE(m.followersCount, u.followersCount)',
      ascLabel: '少ない順', descLabel: '多い順'),
  friends('フォロー数', 'COALESCE(m.friendsCount, u.friendsCount)',
      ascLabel: '少ない順', descLabel: '多い順'),
  statuses('投稿数', 'COALESCE(m.statusesCount, u.statusesCount)',
      ascLabel: '少ない順', descLabel: '多い順'),
  ratio(
      'F比',
      'CAST(COALESCE(m.followersCount, u.followersCount) AS REAL) / '
          'NULLIF(COALESCE(m.friendsCount, u.friendsCount), 0)',
      ascLabel: '低い順',
      descLabel: '高い順'),
  screenName('@ID', 'u.screenName COLLATE NOCASE',
      ascLabel: 'A → Z', descLabel: 'Z → A'),
  captured('取得順', 'm.rowid', ascLabel: '古い順', descLabel: '新しい順');

  const FollowSortKey(this.label, this.expression,
      {required this.ascLabel, required this.descLabel});

  final String label;

  /// 並び替えに使う SQL 式 (向きは含まない)
  final String expression;
  final String ascLabel;
  final String descLabel;

  String directionLabel(bool descending) => descending ? descLabel : ascLabel;
}

/// 一覧の並び替え。基準と向きを別々に持つ
class FollowSort {
  const FollowSort(this.key, {this.descending = true});

  final FollowSortKey key;
  final bool descending;

  static const initial = FollowSort(FollowSortKey.followers);

  FollowSort withKey(FollowSortKey key) =>
      FollowSort(key, descending: descending);
  FollowSort withDirection(bool descending) =>
      FollowSort(key, descending: descending);

  String get label => '${key.label}（${key.directionLabel(descending)}）';

  /// 投稿数は取れていない相手が居る (X の旧レスポンス由来)。
  /// 昇順のときに NULL が先頭に来ると「投稿 0 件」と見分けが付かないので、
  /// 向きにかかわらず末尾へ送る。
  String get sql => '(${key.expression}) IS NULL, '
      '${key.expression} ${descending ? 'DESC' : 'ASC'}';

  @override
  bool operator ==(Object other) =>
      other is FollowSort &&
      other.key == key &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(key, descending);
}

/// 一覧の絞り込み。
///
/// [protected] / [verified] は 3 状態。null は「指定なし」で、
/// true なら該当する相手だけ、false なら該当する相手を除く。
class FollowFilter {
  const FollowFilter({this.search = '', this.protected, this.verified});

  final String search;
  final bool? protected;
  final bool? verified;

  static const none = FollowFilter();

  bool get isEmpty => search.isEmpty && protected == null && verified == null;

  /// 検索以外の絞り込みが何個かかっているか (バッジ表示用)
  int get activeCount =>
      (protected == null ? 0 : 1) + (verified == null ? 0 : 1);

  FollowFilter copyWith({
    String? search,
    bool? protected,
    bool? verified,
    bool clearProtected = false,
    bool clearVerified = false,
  }) =>
      FollowFilter(
        search: search ?? this.search,
        protected: clearProtected ? null : (protected ?? this.protected),
        verified: clearVerified ? null : (verified ?? this.verified),
      );

  /// WHERE に足す条件と引数。何も無ければ空文字
  ({String sql, List<Object?> args}) get clause {
    final parts = <String>[];
    final args = <Object?>[];
    if (search.isNotEmpty) {
      parts.add('(u.screenName LIKE ? OR u.name LIKE ?)');
      args..add('%$search%')..add('%$search%');
    }
    if (protected != null) {
      parts.add('u.isProtected = ?');
      args.add(protected! ? 1 : 0);
    }
    if (verified != null) {
      parts.add('u.verified = ?');
      args.add(verified! ? 1 : 0);
    }
    return (
      sql: parts.isEmpty ? '' : ' AND ${parts.join(' AND ')}',
      args: args,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FollowFilter &&
      other.search == search &&
      other.protected == protected &&
      other.verified == verified;

  @override
  int get hashCode => Object.hash(search, protected, verified);
}

/// 2 世代間での件数の変化
class FollowCountChange {
  const FollowCountChange({
    required this.user,
    this.oldFollowers,
    this.newFollowers,
    this.oldStatuses,
    this.newStatuses,
  });

  final FollowUser user;
  final int? oldFollowers;
  final int? newFollowers;
  final int? oldStatuses;
  final int? newStatuses;

  int? get followersDelta => (oldFollowers == null || newFollowers == null)
      ? null
      : newFollowers! - oldFollowers!;
  int? get statusesDelta => (oldStatuses == null || newStatuses == null)
      ? null
      : newStatuses! - oldStatuses!;
}

/// 1 回の走査
class FollowSnapshot {
  const FollowSnapshot({
    required this.id,
    required this.service,
    required this.targetHandle,
    required this.kind,
    required this.startedAt,
    required this.status,
    required this.collectedCount,
    this.totalExpected,
    this.sessionAccountId,
    this.completedAt,
    this.reason,
    this.cursor,
  });

  final int id;
  final SnsService service;
  final String targetHandle;
  final String kind;
  final String? sessionAccountId;
  final DateTime startedAt;
  final DateTime? completedAt;

  /// running / completed / interrupted
  final String status;
  final String? reason;
  final String? cursor;
  final int collectedCount;

  /// プロフィール上の件数。取りこぼしの検出に使う
  final int? totalExpected;

  /// 想定件数に対する取得率。想定が不明なら null
  double? get completeness {
    final t = totalExpected;
    if (t == null || t <= 0) return null;
    return (collectedCount / t).clamp(0.0, 1.0);
  }

  bool get isCompleted => status == 'completed';
  bool get isResumable => status != 'completed' && cursor != null;

  factory FollowSnapshot.fromRow(Map<String, Object?> r) => FollowSnapshot(
        id: r['id'] as int,
        service: _serviceOf(r['service']),
        targetHandle: r['targetHandle'] as String,
        kind: r['kind'] as String,
        sessionAccountId: r['sessionAccountId'] as String?,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(r['startedAt'] as int),
        completedAt: r['completedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['completedAt'] as int),
        status: r['status'] as String,
        reason: r['reason'] as String?,
        cursor: r['cursor'] as String?,
        collectedCount: (r['collectedCount'] as int?) ?? 0,
        totalExpected: r['totalExpected'] as int?,
      );
}

/// ブロック調査 1 回
class BlockRun {
  const BlockRun({
    required this.id,
    required this.service,
    required this.targetHandle,
    required this.origin,
    required this.startedAt,
    required this.status,
    this.sessionAccountId,
    this.completedAt,
  });

  final int id;
  final SnsService service;
  final String targetHandle;

  /// 起点。'following' / 'followers' / 'mutual'
  final String origin;
  final String? sessionAccountId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String status;

  bool get isCompleted => status == 'completed';

  String get originLabel => switch (origin) {
        'followers' => 'フォロワー',
        'mutual' => '相互',
        _ => 'フォロー',
      };

  factory BlockRun.fromRow(Map<String, Object?> r) => BlockRun(
        id: r['id'] as int,
        service: _serviceOf(r['service']),
        targetHandle: r['targetHandle'] as String,
        origin: (r['origin'] as String?) ?? 'following',
        sessionAccountId: r['sessionAccountId'] as String?,
        startedAt: DateTime.fromMillisecondsSinceEpoch(r['startedAt'] as int),
        completedAt: r['completedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['completedAt'] as int),
        status: r['status'] as String,
      );
}

/// 調査の走査対象 1 人
class BlockSource {
  const BlockSource({
    required this.runId,
    required this.restId,
    required this.screenName,
    required this.position,
    required this.status,
    this.friendsCount,
    this.cursor,
    this.collected = 0,
    this.reason,
  });

  final int runId;
  final String restId;
  final String screenName;
  final int? friendsCount;
  final int position;

  /// pending / running / done / skipped / failed
  final String status;

  /// 途中まで取れているときの再開位置
  final String? cursor;
  final int collected;
  final String? reason;

  factory BlockSource.fromRow(Map<String, Object?> r) => BlockSource(
        runId: r['runId'] as int,
        restId: r['restId'] as String,
        screenName: r['screenName'] as String,
        friendsCount: r['friendsCount'] as int?,
        position: (r['position'] as int?) ?? 0,
        status: r['status'] as String,
        cursor: r['cursor'] as String?,
        collected: (r['collected'] as int?) ?? 0,
        reason: r['reason'] as String?,
      );
}

/// 調査の進み具合。途中でも見られるように、いつでも数えられる
class BlockRunProgress {
  const BlockRunProgress({
    required this.totalSources,
    required this.doneSources,
    required this.skippedSources,
    required this.scanned,
    required this.blockedBy,
    required this.blocking,
    required this.muting,
  });

  final int totalSources;
  final int doneSources;
  final int skippedSources;

  /// 関係を記録できた延べ件数
  final int scanned;
  final int blockedBy;
  final int blocking;
  final int muting;

  double get ratio => totalSources == 0 ? 0 : doneSources / totalSources;
}

/// 見つかった相手と、どこで見つかったか
class BlockFinding {
  const BlockFinding({
    required this.user,
    required this.sourceCount,
    required this.sourceNames,
  });

  final FollowUser user;

  /// 何人のフォロー先に現れたか
  final int sourceCount;

  /// 発見元の @ID をカンマで並べたもの (表示用)
  final String sourceNames;
}
