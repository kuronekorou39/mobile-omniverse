import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/follow_user.dart';

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
  static const _version = 4;

  Database? _db;

  @visibleForTesting
  Database? dbOverride;

  Future<Database> get _database async {
    if (dbOverride != null) return dbOverride!;
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, _fileName),
      version: _version,
      onCreate: (db, _) async {
        await _createSchema(db);
        await _upgradeToV2(db);
        await _upgradeToV3(db);
        await _upgradeToV4(db);
      },
      onUpgrade: (db, from, to) async {
        if (from < 2) await _upgradeToV2(db);
        if (from < 3) await _upgradeToV3(db);
        if (from < 4) await _upgradeToV4(db);
      },
      onConfigure: (db) async =>
          db.execute('PRAGMA foreign_keys = ON'),
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
  /// 「ツイート数がいくつ増えたか」を後から出せないため。
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
      SELECT targetHandle, MAX(sessionAccountId), MIN(startedAt)
      FROM snapshots GROUP BY targetHandle
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

  Future<FollowTarget?> getTarget(String handle) async {
    final db = await _database;
    final rows = await db.query('targets',
        where: 'handle = ?', whereArgs: [_norm(handle)], limit: 1);
    return rows.isEmpty ? null : FollowTarget.fromRow(rows.first);
  }

  Future<void> upsertTarget(FollowTarget target) async {
    final db = await _database;
    await db.insert('targets', target.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 対象と、そこに紐づくスナップショット一式を消す
  Future<void> deleteTarget(String handle) async {
    final db = await _database;
    final h = _norm(handle);
    await db.transaction((txn) async {
      await txn.delete('snapshot_members',
          where: 'snapshotId IN (SELECT id FROM snapshots WHERE targetHandle = ?)',
          whereArgs: [h]);
      await txn.delete('snapshots', where: 'targetHandle = ?', whereArgs: [h]);
      await txn.delete('targets', where: 'handle = ?', whereArgs: [h]);
    });
    await pruneOrphanUsers();
  }

  static String _norm(String handle) =>
      handle.replaceFirst('@', '').toLowerCase();

  /// 対象 × 種別の「最新の完了済み」スナップショット
  Future<FollowSnapshot?> latestCompleted(String handle, String kind) async {
    final db = await _database;
    final rows = await db.query('snapshots',
        where: "targetHandle = ? AND kind = ? AND status = 'completed'",
        whereArgs: [_norm(handle), kind],
        orderBy: 'startedAt DESC',
        limit: 1);
    return rows.isEmpty ? null : FollowSnapshot.fromRow(rows.first);
  }

  /// 対象の未完了スナップショット（再開候補）。新しい順
  Future<List<FollowSnapshot>> resumableFor(String handle) async {
    final db = await _database;
    final rows = await db.query('snapshots',
        where: "targetHandle = ? AND status <> 'completed' AND cursor IS NOT NULL",
        whereArgs: [_norm(handle)],
        orderBy: 'startedAt DESC');
    return rows.map(FollowSnapshot.fromRow).toList();
  }

  // ─── ストレージ使用量 ───

  /// DB ファイルの実サイズ
  Future<int> databaseSizeBytes() async {
    if (dbOverride != null) return 0;
    final file = File(p.join(await getDatabasesPath(), _fileName));
    return file.existsSync() ? file.lengthSync() : 0;
  }

  /// 対象ごとの snapshot_members 行数。使用量の按分に使う
  Future<Map<String, int>> memberRowsByTarget() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT s.targetHandle AS h, COUNT(*) AS c '
      'FROM snapshot_members m JOIN snapshots s ON s.id = m.snapshotId '
      'GROUP BY s.targetHandle',
    );
    return {
      for (final r in rows) r['h'] as String: (r['c'] as int?) ?? 0,
    };
  }

  /// 保持サイズの上限を超えていたら、古い完了スナップショットから削除する。
  /// 差分が取れなくなるので、(対象 × 種別) ごとに [keepPerKind] 世代は必ず残す。
  Future<int> pruneToSizeLimit(int limitBytes, {int keepPerKind = 2}) async {
    if (await databaseSizeBytes() <= limitBytes) return 0;
    final db = await _database;

    final victims = await db.rawQuery('''
      SELECT id FROM (
        SELECT id, startedAt, ROW_NUMBER() OVER (
          PARTITION BY targetHandle, kind ORDER BY startedAt DESC
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
        if (await databaseSizeBytes() <= limitBytes) break;
      }
    }
    if (deleted > 0) {
      await pruneOrphanUsers();
      await db.execute('VACUUM');
    }
    return deleted;
  }

  // ─── 走査セット (followers + following) ───

  Future<int> startRun(String targetHandle) async {
    final db = await _database;
    return db.insert('runs', {
      'targetHandle': targetHandle,
      'startedAt': DateTime.now().millisecondsSinceEpoch,
      'status': 'running',
    });
  }

  Future<void> finishRun(int runId, {required bool completed}) async {
    final db = await _database;
    await db.update(
      'runs',
      {
        'status': completed ? 'completed' : 'interrupted',
        'completedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [runId],
    );
  }

  Future<List<FollowRun>> listRuns({int limit = 50}) async {
    final db = await _database;
    final rows = await db.query('runs',
        orderBy: 'startedAt DESC', limit: limit);
    return rows.map(FollowRun.fromRow).toList();
  }

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

  /// run に含まれる 2 本のスナップショット ID を返す
  Future<({int? followers, int? following})> runSnapshotIds(int runId) async {
    final db = await _database;
    final rows = await db.query('snapshots',
        columns: ['id', 'kind'], where: 'runId = ?', whereArgs: [runId]);
    int? f, g;
    for (final r in rows) {
      if (r['kind'] == 'followers') f = r['id'] as int;
      if (r['kind'] == 'following') g = r['id'] as int;
    }
    return (followers: f, following: g);
  }

  // ─── スナップショット ───

  /// 走査を開始して snapshot 行を作る
  Future<int> startSnapshot({
    required String targetHandle,
    required String kind,
    String? sessionAccountId,
    int? runId,
  }) async {
    final db = await _database;
    return db.insert('snapshots', {
      'targetHandle': targetHandle,
      'kind': kind,
      'sessionAccountId': sessionAccountId,
      'runId': runId,
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
        batch.insert(
          'users',
          {
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
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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

  /// 中断したまま残っている走査 (再開候補)
  Future<List<FollowSnapshot>> resumableSnapshots() async {
    final db = await _database;
    final rows = await db.query('snapshots',
        where: "status IN ('running', 'interrupted') AND cursor IS NOT NULL",
        orderBy: 'startedAt DESC');
    return rows.map(FollowSnapshot.fromRow).toList();
  }

  Future<List<FollowSnapshot>> listSnapshots({
    String? targetHandle,
    String? kind,
    int limit = 100,
  }) async {
    final db = await _database;
    final where = <String>[];
    final args = <Object?>[];
    if (targetHandle != null) {
      where.add('targetHandle = ?');
      args.add(targetHandle);
    }
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    final rows = await db.query(
      'snapshots',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'startedAt DESC',
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
    String? search,
    FollowSortOrder sort = FollowSortOrder.followersDesc,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await _database;
    final filtering = search != null && search.isNotEmpty;
    // 件数は「走査時点の値」を優先し、無ければ users の最新値で代用する
    final rows = await db.rawQuery(
      'SELECT u.*, '
      'COALESCE(m.followersCount, u.followersCount) AS snapFollowers, '
      'COALESCE(m.friendsCount, u.friendsCount) AS snapFriends, '
      'COALESCE(m.statusesCount, u.statusesCount) AS snapStatuses '
      'FROM snapshot_members m JOIN users u ON u.restId = m.restId '
      'WHERE m.snapshotId = ?'
      '${filtering ? ' AND (u.screenName LIKE ? OR u.name LIKE ?)' : ''} '
      'ORDER BY ${sort.sql}, u.restId '
      'LIMIT ? OFFSET ?',
      [
        snapshotId,
        if (filtering) ...['%$search%', '%$search%'],
        limit,
        offset,
      ],
    );
    return rows.map(_userFromSnapshotRow).toList();
  }

  /// 相互 (followers ∩ following)。[onlyIn] を指定すると片側だけを返す
  ///   null      → 相互
  ///   'followers' → フォロワーだがフォローしていない (片思われ)
  ///   'following' → フォローしているがフォロワーではない (片思い)
  Future<List<FollowUser>> relationMembers({
    required int followersSnapshotId,
    required int followingSnapshotId,
    String? onlyIn,
    FollowSortOrder sort = FollowSortOrder.followersDesc,
    int limit = 100,
    int offset = 0,
  }) async {
    final f = followersSnapshotId, g = followingSnapshotId;
    final db = await _database;
    final (base, other) = switch (onlyIn) {
      'following' => (g, f),
      _ => (f, g),
    };
    final clause = onlyIn == null
        ? 'm.restId IN (SELECT restId FROM snapshot_members WHERE snapshotId = ?)'
        : 'm.restId NOT IN (SELECT restId FROM snapshot_members WHERE snapshotId = ?)';

    final rows = await db.rawQuery(
      'SELECT u.*, '
      'COALESCE(m.followersCount, u.followersCount) AS snapFollowers, '
      'COALESCE(m.friendsCount, u.friendsCount) AS snapFriends, '
      'COALESCE(m.statusesCount, u.statusesCount) AS snapStatuses '
      'FROM snapshot_members m JOIN users u ON u.restId = m.restId '
      'WHERE m.snapshotId = ? AND $clause '
      'ORDER BY ${sort.sql}, u.restId LIMIT ? OFFSET ?',
      [base, other, limit, offset],
    );
    return rows.map(_userFromSnapshotRow).toList();
  }

  /// 両方に居るユーザーの件数の変化 (ツイート数・フォロワー数の推移)
  Future<List<FollowCountChange>> countChanges({
    required int oldSnapshotId,
    required int newSnapshotId,
    int limit = 200,
  }) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT u.*, '
      'n.followersCount AS newFollowers, o.followersCount AS oldFollowers, '
      'n.statusesCount AS newStatuses, o.statusesCount AS oldStatuses '
      'FROM snapshot_members n '
      'JOIN snapshot_members o ON o.restId = n.restId AND o.snapshotId = ? '
      'JOIN users u ON u.restId = n.restId '
      'WHERE n.snapshotId = ? '
      'AND (COALESCE(n.statusesCount,0) <> COALESCE(o.statusesCount,0) '
      '  OR COALESCE(n.followersCount,0) <> COALESCE(o.followersCount,0)) '
      'ORDER BY ABS(COALESCE(n.statusesCount,0) - COALESCE(o.statusesCount,0)) DESC '
      'LIMIT ?',
      [oldSnapshotId, newSnapshotId, limit],
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

  /// 2 つのスナップショットの差分。
  /// added = new にだけ居る / removed = old にだけ居る
  Future<({List<FollowUser> added, List<FollowUser> removed})> diff({
    required int oldSnapshotId,
    required int newSnapshotId,
  }) async {
    final db = await _database;

    Future<List<FollowUser>> onlyIn(int a, int b) async {
      final rows = await db.rawQuery(
        'SELECT u.* FROM snapshot_members m JOIN users u ON u.restId = m.restId '
        'WHERE m.snapshotId = ? AND m.restId NOT IN '
        '(SELECT restId FROM snapshot_members WHERE snapshotId = ?) '
        'ORDER BY u.followersCount DESC',
        [a, b],
      );
      return rows.map(_userFromRow).toList();
    }

    return (
      added: await onlyIn(newSnapshotId, oldSnapshotId),
      removed: await onlyIn(oldSnapshotId, newSnapshotId),
    );
  }

  /// 古い世代を捨てる。対象 × 種別ごとに直近 [keep] 世代だけ残す
  Future<int> pruneOldSnapshots({int keep = 12}) async {
    final db = await _database;
    return db.rawDelete('''
      DELETE FROM snapshots WHERE id IN (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (
            PARTITION BY targetHandle, kind ORDER BY startedAt DESC
          ) AS rn FROM snapshots WHERE status = 'completed'
        ) WHERE rn > ?
      )
    ''', [keep]);
  }

  /// 参照されなくなった users を掃除する
  Future<int> pruneOrphanUsers() async {
    final db = await _database;
    return db.rawDelete(
        'DELETE FROM users WHERE restId NOT IN (SELECT restId FROM snapshot_members)');
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

/// 走査対象。自分のアカウントとは限らない
class FollowTarget {
  const FollowTarget({
    required this.handle,
    required this.addedAt,
    this.displayName = '',
    this.avatarUrl = '',
    this.restId,
    this.sessionAccountId,
    this.followersIntervalDays = 0,
    this.followingIntervalDays = 0,
  });

  /// @ を除いた screen_name（小文字）
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

  FollowTarget copyWith({
    String? displayName,
    String? avatarUrl,
    String? restId,
    String? sessionAccountId,
    int? followersIntervalDays,
    int? followingIntervalDays,
  }) =>
      FollowTarget(
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

/// followers + following を 1 セットで取った走査
class FollowRun {
  const FollowRun({
    required this.id,
    required this.targetHandle,
    required this.startedAt,
    required this.status,
    this.completedAt,
  });

  final int id;
  final String targetHandle;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String status;

  bool get isCompleted => status == 'completed';

  factory FollowRun.fromRow(Map<String, Object?> r) => FollowRun(
        id: r['id'] as int,
        targetHandle: r['targetHandle'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(r['startedAt'] as int),
        completedAt: r['completedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['completedAt'] as int),
        status: r['status'] as String,
      );
}

/// 一覧の並び順。件数は走査時点の値を優先する
enum FollowSortOrder {
  followersDesc('フォロワー数が多い順',
      'COALESCE(m.followersCount, u.followersCount) DESC'),
  followersAsc('フォロワー数が少ない順',
      'COALESCE(m.followersCount, u.followersCount) ASC'),
  friendsDesc('フォロー数が多い順',
      'COALESCE(m.friendsCount, u.friendsCount) DESC'),
  statusesDesc('ツイート数が多い順',
      'COALESCE(m.statusesCount, u.statusesCount) DESC'),
  statusesAsc('ツイート数が少ない順',
      'COALESCE(m.statusesCount, u.statusesCount) ASC'),
  ratioDesc(
      'F比が高い順',
      'CAST(COALESCE(m.followersCount, u.followersCount) AS REAL) / '
          'NULLIF(COALESCE(m.friendsCount, u.friendsCount), 0) DESC'),
  screenName('@ID 順', 'u.screenName COLLATE NOCASE ASC'),
  captured('取得順', 'm.rowid ASC');

  const FollowSortOrder(this.label, this.sql);
  final String label;
  final String sql;
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
