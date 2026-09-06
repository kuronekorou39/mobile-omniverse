import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/follow_user.dart';
import 'follow_db.dart';

/// 集めたデータを CSV で持ち出せるようにする。
///
/// フォロー/フォロワーの取得もつながり調査も、数時間から数日かけて集める。
/// それがアプリの中の SQLite にしか無いと、アプリを消したり作り直したり
/// した時点で消えてしまう。表計算で開ける形にして外に出せるようにする。
///
/// 数万件になるので、全件をメモリに載せず、ページングで読みながら
/// ファイルに書き足していく。
class ExportService {
  ExportService._();
  static final instance = ExportService._();

  /// 1 回の読み出し件数
  static const _page = 500;

  /// フォロー/フォロワーの一覧
  Future<File> snapshotCsv(FollowSnapshot snapshot) async {
    final kind = snapshot.kind == 'followers' ? 'followers' : 'following';
    final file = await _newFile(
        'omniverse_${snapshot.targetHandle}_${kind}_${_stamp(snapshot.startedAt)}');
    final sink = file.openWrite();
    try {
      _writeHeader(sink, const [
        'screen_name',
        'name',
        'rest_id',
        'followers',
        'following',
        'posts',
        'protected',
        'verified',
        'location',
        'created_at',
        'description',
      ]);
      for (var offset = 0;; offset += _page) {
        final rows = await FollowDb.instance
            .members(snapshot.id, limit: _page, offset: offset);
        for (final u in rows) {
          sink.writeln(csvRow(_userCells(u)));
        }
        if (rows.length < _page) break;
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return file;
  }

  /// つながり調査の結果。3 つの関係を relation 列で分けて 1 本にまとめる
  Future<File> blockRunCsv(BlockRun run) async {
    final file = await _newFile(
        'omniverse_${run.targetHandle}_scan_${_stamp(run.startedAt)}');
    final sink = file.openWrite();
    try {
      _writeHeader(sink, const [
        'relation',
        'screen_name',
        'name',
        'rest_id',
        'followers',
        'following',
        'posts',
        'protected',
        'verified',
        'location',
        'created_at',
        'description',
        'source_count',
        'sources',
      ]);
      const relations = {
        'blockedBy': 'ブロックされてる',
        'blocking': 'ブロックしてる',
        'muting': 'ミュートしてる',
      };
      for (final entry in relations.entries) {
        for (var offset = 0;; offset += _page) {
          final rows = await FollowDb.instance.blockFindings(
            runId: run.id,
            relation: entry.key,
            limit: _page,
            offset: offset,
          );
          for (final f in rows) {
            sink.writeln(csvRow([
              entry.value,
              ..._userCells(f.user),
              '${f.sourceCount}',
              f.sourceNames,
            ]));
          }
          if (rows.length < _page) break;
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return file;
  }

  List<String> _userCells(FollowUser u) => [
        u.screenName,
        u.name,
        u.restId,
        '${u.followersCount}',
        '${u.friendsCount}',
        u.statusesCount == null ? '' : '${u.statusesCount}',
        u.isProtected ? 'yes' : '',
        u.verified ? 'yes' : '',
        u.location,
        u.createdAt,
        u.description,
      ];

  Future<File> _newFile(String base) async {
    final dir = await getTemporaryDirectory();
    // 共有シートに出すだけなので一時領域でよい。@ や / が混ざると
    // ファイル名として使えないので落とす
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${dir.path}/$safe.csv');
  }

  /// Excel は BOM が無いと UTF-8 と判断せず日本語が化ける
  void _writeHeader(IOSink sink, List<String> columns) {
    sink.write('\u{FEFF}');
    sink.writeln(csvRow(columns));
  }

  @visibleForTesting
  String csvRow(List<String> cells) => cells.map(csvCell).join(',');

  /// 区切りと引用符と改行を含む値を CSV の作法で囲む。
  /// description は改行を含むので、囲まないと行がずれる
  @visibleForTesting
  String csvCell(String value) {
    if (!value.contains(RegExp(r'[",\r\n]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  String _stamp(DateTime dt) =>
      '${dt.year}${_two(dt.month)}${_two(dt.day)}_${_two(dt.hour)}${_two(dt.minute)}';

  String _two(int v) => v.toString().padLeft(2, '0');
}
