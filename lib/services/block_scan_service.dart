import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/follow_user.dart';
import '../models/sns_service.dart';
import 'account_pool.dart';
import 'debug_log_service.dart';
import 'follow_capture_engine.dart';
import 'follow_capture_job_service.dart';
import 'follow_capture_webview_service.dart';
import 'follow_db.dart';

/// ブロック調査の進み具合。UI はこれを見て描画する
class BlockScanProgress {
  const BlockScanProgress({
    required this.runId,
    required this.targetHandle,
    required this.startedAt,
    this.currentHandle,
    this.currentCollected = 0,
    this.done = 0,
    this.total = 0,
    this.cancelling = false,
  });

  final int runId;
  final String targetHandle;
  final DateTime startedAt;

  /// いま走査している相手
  final String? currentHandle;
  final int currentCollected;

  /// 起点のうち何人を処理し終えたか
  final int done;
  final int total;
  final bool cancelling;

  BlockScanProgress copyWith({
    String? currentHandle,
    int? currentCollected,
    int? done,
    int? total,
    bool? cancelling,
  }) =>
      BlockScanProgress(
        runId: runId,
        targetHandle: targetHandle,
        startedAt: startedAt,
        currentHandle: currentHandle ?? this.currentHandle,
        currentCollected: currentCollected ?? this.currentCollected,
        done: done ?? this.done,
        total: total ?? this.total,
        cancelling: cancelling ?? this.cancelling,
      );
}

/// つながっている人のフォロー先をたどって、実行アカウントとの関係を集める。
///
/// X のフォロー一覧は、各ユーザーに **一覧を取ったアカウントから見た関係**
/// (relationship_perspectives の blocked_by / blocking / muting) を載せて返す。
/// だから「相手のフォロー先を一覧で取る」だけでブロックの有無が分かり、
/// 1 人ずつプロフィールを引き直す必要がない。
///
/// 起点は既存のスナップショット (フォロー / フォロワー / 相互) をそのまま使う。
/// 上から 1 人ずつ、その人のフォロー一覧を走査する。
///
/// 数千人が起点になるので、途中で切れるのが前提。1 ページごとに
/// cursor を保存するので、**中断した相手の続きから**再開できる。
class BlockScanService {
  BlockScanService._();
  static final instance = BlockScanService._();

  /// 走査の送信間隔。フォロー一覧は 1 ページ 2 秒が実測の下限
  static const _accountCooldown = Duration(seconds: 2);

  /// 1 人あたりの上限。フォロー数が事前に分からない相手は、
  /// ここまで取ったら打ち切って次へ進む
  static const _perSourceLimit = FollowDb.blockScanFriendLimit;

  final progress = ValueNotifier<BlockScanProgress?>(null);

  CaptureCancelToken? _cancelToken;
  bool get isRunning => progress.value != null;

  void cancel() {
    _cancelToken?.cancel();
    progress.value = progress.value?.copyWith(cancelling: true);
    DebugLogService.instance.log('BlockScan', '中断を要求');
  }

  /// 起点の一覧から調査を始める。
  ///
  /// [origin] は 'following' / 'followers' / 'mutual'。
  /// 既に取得済みのスナップショットを使うので、ここでは通信しない。
  Future<int?> start({
    required Account account,
    required SnsService service,
    required String handle,
    required String origin,
  }) async {
    if (isRunning) throw StateError('別の調査が実行中です');
    if (account.service != SnsService.x) {
      throw StateError('ブロック調査は X のみ対応しています');
    }

    final db = FollowDb.instance;
    final sources = await _loadSources(service, handle, origin);
    if (sources.isEmpty) return null;

    final runId = await db.startBlockRun(
      service: service,
      targetHandle: handle,
      origin: origin,
      sessionAccountId: account.id,
      sources: sources,
    );
    DebugLogService.instance.log('BlockScan',
        '調査を開始: @$handle の$origin ${sources.length}人 (runId=$runId)');
    await resume(account: account, runId: runId);
    return runId;
  }

  /// 起点になる人たちを、既存のスナップショットから読む
  Future<List<FollowUser>> _loadSources(
      SnsService service, String handle, String origin) async {
    final db = FollowDb.instance;
    final followers = await db.latestCompleted(service, handle, 'followers');
    final following = await db.latestCompleted(service, handle, 'following');

    // 相互は 2 本の突き合わせが要る
    if (origin == 'mutual') {
      if (followers == null || following == null) return const [];
      return _readAll((limit, offset) => db.relationMembers(
            followersSnapshotId: followers.id,
            followingSnapshotId: following.id,
            limit: limit,
            offset: offset,
          ));
    }

    final snapshot = origin == 'followers' ? followers : following;
    if (snapshot == null) return const [];
    return _readAll((limit, offset) =>
        db.members(snapshot.id, limit: limit, offset: offset));
  }

  /// 数千件になるのでページングして読む
  Future<List<FollowUser>> _readAll(
      Future<List<FollowUser>> Function(int limit, int offset) fetch) async {
    const page = 500;
    final all = <FollowUser>[];
    for (var offset = 0;; offset += page) {
      final rows = await fetch(page, offset);
      all.addAll(rows);
      if (rows.length < page) break;
    }
    return all;
  }

  /// 中断した調査を続きから走らせる
  Future<void> resume({required Account account, required int runId}) async {
    if (isRunning) throw StateError('別の調査が実行中です');
    final job = FollowCaptureJobService.instance;
    if (job.isRunning) throw StateError('フォロー/フォロワーの取得が実行中です');
    if (job.isWebViewBusy) throw StateError('他の処理が WebView を使用中です');

    final db = FollowDb.instance;
    final webView = FollowCaptureWebViewService.instance;
    _cancelToken = CaptureCancelToken();

    final stats = await db.blockRunProgress(runId);
    progress.value = BlockScanProgress(
      runId: runId,
      targetHandle: '',
      startedAt: DateTime.now(),
      done: stats.doneSources,
      total: stats.totalSources,
    );

    var completed = false;
    try {
      while (true) {
        if (_cancelToken?.isCancelled ?? false) break;

        final source = await db.nextBlockSource(runId);
        if (source == null) {
          completed = true;
          break;
        }
        await db.markBlockSourceRunning(runId, source.restId);
        progress.value = progress.value?.copyWith(
          currentHandle: source.screenName,
          currentCollected: source.collected,
        );

        await _scanOne(account: account, runId: runId, source: source);

        final s = await db.blockRunProgress(runId);
        progress.value = progress.value
            ?.copyWith(done: s.doneSources, total: s.totalSources);
      }
    } finally {
      await db.finishBlockRun(runId, completed: completed);
      _cancelToken = null;
      progress.value = null;
      await webView.reset();
      // 走査用 WebView は 1 人ごとに畳んでいるので、ここで最後に落とす
      job.hostNeeded.value = false;
      DebugLogService.instance
          .log('BlockScan', '調査を終了 (completed=$completed)');
    }
  }

  /// 1 人ぶんのフォロー一覧を走査する。
  ///
  /// 走査そのものは既存の [FollowCaptureEngine] に任せる。cursor の前進、
  /// レート制限の回避、中断の扱いはすべてそこで面倒を見ている。
  Future<void> _scanOne({
    required Account account,
    required int runId,
    required BlockSource source,
  }) async {
    final db = FollowDb.instance;
    final job = FollowCaptureJobService.instance;
    final webView = FollowCaptureWebViewService.instance;

    // 走査用 WebView は 1 本ごとに作り直す (使い回すと X の SPA が
    // 起動しない)。ここでも 1 人ごとに立て直す
    job.hostNeeded.value = true;
    try {
      await webView.waitForHost();
    } catch (e) {
      await db.finishBlockSource(runId, source.restId,
          status: 'failed', reason: 'WebView を用意できなかった: $e');
      return;
    }

    final pool = AccountPool([account.id], cooldown: _accountCooldown);
    final engine = FollowCaptureEngine(fetchPage: webView.fetchPage);
    var collected = source.collected;

    try {
      final result = await engine.capture(
        targetHandle: source.screenName,
        kind: FollowListKind.following,
        pool: pool,
        accountOf: (_) => account,
        startCursor: source.cursor,
        cancelToken: _cancelToken,
        onBatch: (users, cursor) async {
          collected += users.length;
          await db.addBlockFindings(
            runId: runId,
            sourceRestId: source.restId,
            users: users,
            cursor: cursor,
          );
          progress.value =
              progress.value?.copyWith(currentCollected: collected);
        },
      );

      if (result.completed) {
        await db.finishBlockSource(runId, source.restId, status: 'done');
      } else if (_cancelToken?.isCancelled ?? false) {
        // 中断。status は running のままにして、次回この人の続きから
        DebugLogService.instance.log(
            'BlockScan', '@${source.screenName} を $collected 件で中断');
      } else {
        await db.finishBlockSource(runId, source.restId,
            status: 'failed', reason: result.reason.name);
      }
    } on CaptureCancelledException {
      DebugLogService.instance
          .log('BlockScan', '@${source.screenName} を中断');
    } catch (e) {
      await db.finishBlockSource(runId, source.restId,
          status: 'failed', reason: '$e');
      debugPrint('[BlockScan] @${source.screenName} 失敗: $e');
    } finally {
      // 上限に達していたら、完了扱いにして次へ進む。
      // 事前にフォロー数が分からない相手はここで止める
      if (collected >= _perSourceLimit) {
        await db.finishBlockSource(runId, source.restId,
            status: 'done', reason: 'フォローが多いため $collected 件で打ち切り');
      }
      await webView.reset();
      job.hostNeeded.value = false;
    }
  }
}
