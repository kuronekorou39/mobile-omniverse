import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/follow_user.dart';
import '../models/x_rate_limit.dart';
import 'account_pool.dart';
import 'debug_log_service.dart';
import 'follow_list_parser.dart';
import 'x_api_service.dart';

/// 1 ページ分を取得する処理。
///
/// X は `x-client-transaction-id` を検証するため、Dart の http から直接叩くと
/// 404 になる (実測済み)。本番では [FollowCaptureWebViewService] が
/// WebView のページコンテキストで実行する。エンジンはこの口しか知らない。
typedef FollowPageFetcher = Future<XFollowListPage> Function({
  required Account account,
  required String targetHandle,
  required FollowListKind kind,
  String? cursor,
  CaptureCancelToken? cancelToken,
});

/// 取得する一覧の種別
enum FollowListKind {
  following,
  followers;

  String get operationName => this == following ? 'Following' : 'Followers';
}

/// 走査が終わった / 中断した理由
enum FollowCaptureReason {
  /// 末尾カーソル ("0|...") に到達 — 正常完了
  terminal,

  /// cursor が返らなくなった — 正常完了
  noCursor,

  /// 空バッチで cursor も進まない — 正常完了扱い
  stalled,

  /// 呼び出し側からキャンセルされた
  aborted,

  /// 使えるアカウントが無くなった
  poolEmpty,

  /// 連続失敗が閾値に達した
  circuitBreak,

  /// ネットワーク例外が連続した
  networkError,

  /// 5xx 等が連続した
  httpError,

  /// ラウンド上限に達した
  maxRounds,
}

/// 1 ターゲット × 1 種別の走査結果
class FollowCaptureResult {
  const FollowCaptureResult({
    required this.completed,
    required this.totalUsers,
    required this.reason,
    this.cursor,
    this.httpStatus,
    this.rateLimit,
  });

  /// 全件取得しきったか
  final bool completed;
  final int totalUsers;
  final FollowCaptureReason reason;

  /// 中断時の再開位置。次回はここから続けられる
  final String? cursor;
  final int? httpStatus;
  final XRateLimit? rateLimit;
}

/// 進捗通知
class FollowCaptureProgress {
  const FollowCaptureProgress({
    required this.collected,
    required this.round,
    required this.poolSize,
    this.cursor,
    this.rateLimit,
  });

  final int collected;
  final int round;
  final int poolSize;
  final String? cursor;
  final XRateLimit? rateLimit;
}

/// 待機中の表示用。待機が終わると null が通知される
class FollowCaptureWaiting {
  const FollowCaptureWaiting({
    required this.reason,
    required this.total,
    required this.startedAt,
  });

  final String reason;
  final Duration total;
  final DateTime startedAt;
}

/// キャンセルされた待機から抜けるための例外。
/// エンジンは「通信エラー」ではなく中断として扱う。
class CaptureCancelledException implements Exception {
  const CaptureCancelledException();

  @override
  String toString() => '走査が中断されました';
}

/// 走査のキャンセル用トークン
class CaptureCancelToken {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const CaptureCancelledException();
  }

  /// [duration] 待つ。待っている間にキャンセルされたら残りを待たずに返る。
  ///
  /// 中断ボタンの効きは「一番長い待機がキャンセルを見ているか」で決まる。
  /// 待つ処理は必ずこれを通すこと。
  static Future<void> sleep(Duration duration, [CaptureCancelToken? token]) {
    if (duration <= Duration.zero) return Future.value();
    if (token == null) return Future.delayed(duration);
    if (token.isCancelled) return Future.value();
    return Future.any([Future.delayed(duration), token.whenCancelled]);
  }

  /// [future] の完了を待つ。待っている間にキャンセルされたら
  /// [CaptureCancelledException] で抜ける。
  ///
  /// 元の future は放置される。WebView 内の fetch はページを畳めば止まるので、
  /// 待ち続けるより先に抜けたほうが中断が速い。
  static Future<T> race<T>(Future<T> future, [CaptureCancelToken? token]) {
    if (token == null) return future;
    if (token.isCancelled) {
      return Future.error(const CaptureCancelledException());
    }
    return Future.any([
      future,
      token.whenCancelled
          .then<T>((_) => throw const CaptureCancelledException()),
    ]);
  }
}

/// フォロー/フォロワー一覧を cursor ページングで全件取得するエンジン
///
/// Follow-Capture-Tool の paginator.js を移植したもの。要点は 2 つ:
///
/// 1. **cursor を前進させるのは HTTP 200 のときだけ。**
///    失敗時に進めると取りこぼしが発生する。
/// 2. **レート制限は踏む前に避ける。** [AccountPool.dynamicInterval] が
///    残量に応じて送信間隔を延ばす。
///
/// 拡張版にあった「タブ傍受 + txId プール補充」は、アプリが
/// x-client-transaction-id を毎リクエスト生成するため不要になっている。
/// MV3 の SW keep-alive ハック (alarms-sleep.js) も、Android では
/// foreground service / WorkManager 側の責務なのでここには無い。
class FollowCaptureEngine {
  FollowCaptureEngine({required this.fetchPage});

  /// 1 ページ取得する処理。本番では WebView 経由、テストでは差し替える。
  final FollowPageFetcher fetchPage;

  /// 待機処理の差し替え口 (テストで実時間を待たないため)。
  ///
  /// [AccountPool] のクールダウン判定は実時刻を見るので、これを差し替える
  /// テストでは `cooldown: Duration.zero` のプールを使うこと。さもないと
  /// クールダウンが明けるまで空回りする。
  @visibleForTesting
  Future<void> Function(Duration duration)? sleepOverride;

  /// ネットワーク例外・5xx がこの回数連続したら諦める
  static const maxConsecutiveNetworkErrors = 5;

  /// ネットワーク再試行の基準待ち時間 (連続回数に比例して伸ばす)
  static const networkRetryBase = Duration(seconds: 30);

  /// 429 で reset 時刻が読めなかったときの待ち時間
  static const rateLimitFallbackWait = Duration(seconds: 60);

  /// 暴走防止のラウンド上限
  static const defaultMaxRounds = 5000;

  /// [targetHandle] の [kind] 一覧を全件取得する。
  ///
  /// [accountOf] は走査に使うアカウントを accountId から引くコールバック。
  /// [startCursor] を渡すと途中から再開する。
  /// 1 ページの件数は X 自身のリクエストに従うので指定しない。
  Future<FollowCaptureResult> capture({
    required String targetHandle,
    required FollowListKind kind,
    required AccountPool pool,
    required Account? Function(String accountId) accountOf,
    String? startCursor,
    int maxRounds = defaultMaxRounds,
    CaptureCancelToken? cancelToken,
    Future<void> Function(List<FollowUser> users, String? cursor)? onBatch,
    void Function(FollowCaptureProgress progress)? onProgress,
    void Function(FollowCaptureWaiting? waiting)? onWaiting,
  }) async {
    var cursor = startCursor;
    var totalUsers = 0;
    var round = 0;
    var consecutiveNetworkErrors = 0;
    DateTime? lastFetchAt;
    XRateLimit? lastRateLimit;

    bool cancelled() => cancelToken?.isCancelled ?? false;

    FollowCaptureResult finish(
      FollowCaptureReason reason, {
      required bool completed,
      int? httpStatus,
    }) {
      onWaiting?.call(null);
      _log(kind,
          'finish: ${reason.name} (total=$totalUsers, round=$round, completed=$completed)');
      return FollowCaptureResult(
        completed: completed,
        totalUsers: totalUsers,
        reason: reason,
        cursor: cursor,
        httpStatus: httpStatus,
        rateLimit: lastRateLimit,
      );
    }

    Future<void> wait(String reason, Duration duration) async {
      if (duration <= Duration.zero) return;
      onWaiting?.call(FollowCaptureWaiting(
          reason: reason, total: duration, startedAt: DateTime.now()));
      await _sleep(duration, cancelToken);
      onWaiting?.call(null);
    }

    // 再開 cursor がすでに末尾なら何もしない
    if (FollowListParser.isTerminalCursor(cursor)) {
      return finish(FollowCaptureReason.terminal, completed: true);
    }

    while (true) {
      if (cancelled()) return finish(FollowCaptureReason.aborted, completed: false);
      if (round > maxRounds) {
        return finish(FollowCaptureReason.maxRounds, completed: false);
      }
      if (pool.isEmpty) {
        return finish(FollowCaptureReason.poolEmpty, completed: false);
      }

      // --- 1. アカウント選択 (全員クールダウン中なら待つ) ---
      final accountId = pool.pick();
      if (accountId == null) {
        final w = pool.timeUntilNext();
        await wait('アカウントのクールダウン待ち (${pool.size}件)', w);
        continue;
      }

      final account = accountOf(accountId);
      if (account == null) {
        _log(kind, 'アカウント $accountId を引けない → プールから除外');
        pool.markFailed(accountId);
        if (pool.shouldCircuitBreak) {
          return finish(FollowCaptureReason.circuitBreak, completed: false);
        }
        continue;
      }

      // --- 2. 送信間隔の確保 (残量に応じて動的に延びる) ---
      final interval = pool.dynamicInterval(accountId);
      if (lastFetchAt != null) {
        final sinceLast = DateTime.now().difference(lastFetchAt);
        if (sinceLast < interval) {
          await wait('送信間隔の調整 (${interval.inSeconds}秒)', interval - sinceLast);
          if (cancelled()) {
            return finish(FollowCaptureReason.aborted, completed: false);
          }
        }
      }

      // --- 3. fetch ---
      final XFollowListPage page;
      try {
        page = await fetchPage(
          account: account,
          targetHandle: targetHandle,
          kind: kind,
          cursor: cursor,
          cancelToken: cancelToken,
        );
        lastFetchAt = DateTime.now();
      } catch (e) {
        // 取得口の中の待機から抜けてきた場合も含めて、まず中断を見る。
        // 再試行に載せてしまうと中断ボタンが数十秒効かなくなる。
        if (cancelled()) {
          return finish(FollowCaptureReason.aborted, completed: false);
        }
        consecutiveNetworkErrors++;
        _log(kind,
            'network error at round $round ($consecutiveNetworkErrors): $e');
        if (consecutiveNetworkErrors > maxConsecutiveNetworkErrors) {
          return finish(FollowCaptureReason.networkError, completed: false);
        }
        await wait('通信エラーの再試行 ($consecutiveNetworkErrors回目)',
            networkRetryBase * consecutiveNetworkErrors);
        continue;
      }

      pool.updateRateLimit(accountId, page.rateLimit);
      if (page.rateLimit != null) lastRateLimit = page.rateLimit;

      // --- 4. ステータス別分岐 (cursor は 200 のときだけ前進) ---
      if (page.statusCode == 429) {
        pool.markUsed(accountId);
        final untilReset = page.rateLimit?.untilReset();
        final w = untilReset == null
            ? rateLimitFallbackWait
            : untilReset + AccountPool.resetMargin;
        _log(kind, '429 → ${w.inSeconds}秒待機');
        await wait('レート制限の解除待ち', w);
        continue;
      }

      if (page.statusCode == 401 || page.statusCode == 403) {
        _log(kind, '${page.statusCode} → $accountId をプールから除外');
        pool.markFailed(accountId);
        onProgress?.call(FollowCaptureProgress(
          collected: totalUsers,
          round: round,
          poolSize: pool.size,
          cursor: cursor,
          rateLimit: lastRateLimit,
        ));
        if (pool.shouldCircuitBreak) {
          return finish(FollowCaptureReason.circuitBreak, completed: false);
        }
        continue;
      }

      if (page.statusCode == 404) {
        // 取得口の側で「txId 失効 → 捕り直して再試行」まで済んでいる。
        // それでも 404 ならこのアカウント固有の問題 (制限等) と見て外す。
        _log(kind, '404 (再捕獲後も) → $accountId をプールから除外');
        pool.markFailed(accountId);
        if (pool.shouldCircuitBreak) {
          return finish(FollowCaptureReason.circuitBreak, completed: false);
        }
        continue;
      }

      if (page.statusCode == XApiService.followListBadJson) {
        pool.markUsed(accountId);
        _log(kind, 'JSON として解釈できない応答 → $accountId をプールから除外');
        pool.markFailed(accountId);
        if (pool.shouldCircuitBreak) {
          return finish(FollowCaptureReason.circuitBreak, completed: false);
        }
        continue;
      }

      if (!page.isSuccess) {
        pool.markUsed(accountId);
        consecutiveNetworkErrors++;
        _log(kind,
            'http ${page.statusCode} at round $round ($consecutiveNetworkErrors)');
        if (consecutiveNetworkErrors > maxConsecutiveNetworkErrors) {
          return finish(FollowCaptureReason.httpError,
              completed: false, httpStatus: page.statusCode);
        }
        await wait('HTTP ${page.statusCode} の再試行', networkRetryBase);
        continue;
      }

      // --- 5. 成功 ---
      pool.markUsed(accountId);
      pool.markSuccess();
      consecutiveNetworkErrors = 0;

      totalUsers += page.users.length;
      if (page.users.isNotEmpty) {
        await onBatch?.call(page.users, page.cursor);
      }

      onProgress?.call(FollowCaptureProgress(
        collected: totalUsers,
        round: round,
        poolSize: pool.size,
        cursor: page.cursor,
        rateLimit: page.rateLimit ?? lastRateLimit,
      ));

      // 空バッチで cursor も動かないなら、それ以上進めない
      if (page.users.isEmpty && page.cursor == cursor) {
        return finish(FollowCaptureReason.stalled, completed: true);
      }

      cursor = page.cursor; // ★ cursor 前進はここだけ
      round++;

      if (cursor == null) {
        return finish(FollowCaptureReason.noCursor, completed: true);
      }
      if (FollowListParser.isTerminalCursor(cursor)) {
        return finish(FollowCaptureReason.terminal, completed: true);
      }
    }
  }

  Future<void> _sleep(Duration duration, CaptureCancelToken? token) {
    final override = sleepOverride;
    if (override != null) return override(duration);
    return CaptureCancelToken.sleep(duration, token);
  }

  static void _log(FollowListKind kind, String message) {
    debugPrint('[FollowCapture/${kind.operationName}] $message');
    DebugLogService.instance
        .log('FollowCapture', '${kind.operationName}: $message');
  }
}
