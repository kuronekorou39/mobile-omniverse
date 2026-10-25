import 'package:flutter/foundation.dart';

import 'follow_db.dart';

/// 既存の調査の「人気」の集計表を、裏で起点 1 人ずつ作り直す進み具合
class PopularBuildProgress {
  const PopularBuildProgress({
    required this.runId,
    required this.done,
    required this.total,
  });

  final int runId;

  /// 集計に反映した起点の数 / 走査の終わった起点の数
  final int done;
  final int total;
}

/// 集計表（block_popular）ができる前に走った調査のぶんを、
/// block_findings から起点ごとに積み直す。
///
/// 一度に全部やると 1,000 万行の調査では分の単位で DB を塞ぐので、
/// 起点 1 人ぶんずつ区切って進める。人気の一覧はその途中でも開け、
/// 数字が増えていくのが見える。新しい調査は走査しながら積むので、
/// ここに来ることはない
class BlockPopularBuilder {
  BlockPopularBuilder._();

  static final instance = BlockPopularBuilder._();

  /// 作り直し中の調査。走っていなければ null
  final progress = ValueNotifier<PopularBuildProgress?>(null);

  bool get isRunning => progress.value != null;

  /// [runId] に反映していない起点があれば、終わるまで裏で進める。
  /// 既に別の調査を作り直していれば何もしない（次に開いたときに続く）
  Future<void> ensureBuilt(int runId) async {
    if (isRunning) return;
    final db = FollowDb.instance;
    var next = await db.nextUnaggregatedSource(runId);
    if (next == null) return;

    final p = await db.popularBuildProgress(runId);
    progress.value =
        PopularBuildProgress(runId: runId, done: p.done, total: p.total);
    try {
      while (next != null) {
        await db.aggregateSource(runId, next.restId);
        final p = await db.popularBuildProgress(runId);
        progress.value =
            PopularBuildProgress(runId: runId, done: p.done, total: p.total);
        // 画面の描画や走査の書き込みに順番を譲る
        await Future<void>.delayed(Duration.zero);
        next = await db.nextUnaggregatedSource(runId);
      }
    } catch (e) {
      debugPrint('[BlockPopularBuilder] 作り直しに失敗: $e');
    } finally {
      progress.value = null;
    }
  }
}
