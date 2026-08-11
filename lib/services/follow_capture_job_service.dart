import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/x_rate_limit.dart';
import 'account_pool.dart';
import 'follow_capture_engine.dart';
import 'follow_capture_webview_service.dart';
import 'follow_db.dart';
import 'x_api_service.dart';

/// 実行中の走査の状態。UI はこれを見て描画する
class FollowJobProgress {
  const FollowJobProgress({
    required this.snapshotId,
    required this.targetHandle,
    required this.kind,
    required this.collected,
    required this.round,
    required this.startedAt,
    this.rateLimit,
    this.waitingReason,
    this.waitingUntil,
    this.cancelling = false,
  });

  final int snapshotId;
  final String targetHandle;
  final FollowListKind kind;
  final int collected;
  final int round;
  final DateTime startedAt;
  final XRateLimit? rateLimit;

  /// 待機中に理由と復帰予定時刻が入る。動いている間は null
  final String? waitingReason;
  final DateTime? waitingUntil;

  /// 中断を要求済み。実際に止まるまでの間 UI にそう見せるためのフラグ。
  /// 通信中のページが 1 枚残っていることがあるので、押した瞬間 = 停止ではない
  final bool cancelling;

  FollowJobProgress copyWith({
    int? collected,
    int? round,
    XRateLimit? rateLimit,
    String? waitingReason,
    DateTime? waitingUntil,
    bool clearWaiting = false,
    bool? cancelling,
  }) =>
      FollowJobProgress(
        snapshotId: snapshotId,
        targetHandle: targetHandle,
        kind: kind,
        collected: collected ?? this.collected,
        round: round ?? this.round,
        startedAt: startedAt,
        rateLimit: rateLimit ?? this.rateLimit,
        waitingReason: clearWaiting ? null : (waitingReason ?? this.waitingReason),
        waitingUntil: clearWaiting ? null : (waitingUntil ?? this.waitingUntil),
        cancelling: cancelling ?? this.cancelling,
      );
}

/// エンジンと DB をつないで 1 本の走査ジョブとして実行するサービス。
///
/// ページングのペースは [FollowCaptureWebViewService] の txId プールが握るので、
/// ここのアカウントクールダウンは短くしておき、二重に待たせない。
/// レート制限の残量に応じた減速は [AccountPool.dynamicInterval] が担当する。
class FollowCaptureJobService {
  FollowCaptureJobService._();
  static final instance = FollowCaptureJobService._();

  /// txId プールがペースを握るので、ここは短くしておく
  static const _accountCooldown = Duration(seconds: 2);

  static const _prefAutoRun = 'follow_capture_auto_run';
  static const _prefSizeLimit = 'follow_capture_size_limit';
  static const _prefAutoRegistered = 'follow_capture_auto_registered';

  /// 保持サイズの上限。超えたら古い世代から間引く
  static const sizeLimitChoices = <int>[
    50 * 1024 * 1024,
    100 * 1024 * 1024,
    200 * 1024 * 1024,
    500 * 1024 * 1024,
  ];

  /// アプリ起動時に「再開 / スケジュール実行」を自動で走らせるか
  bool autoRunOnLaunch = true;

  /// 保持サイズの上限（既定 200MB）
  int sizeLimitBytes = 200 * 1024 * 1024;

  /// 走査対象として自動登録済みの自分のアカウント ID。
  ///
  /// 自分のアカウントは対象一覧に自動で並ぶが、「一度でも並べたか」を
  /// 覚えておかないと、ユーザーが削除しても次に画面を開いた瞬間に
  /// 復活してしまい、削除できないように見える。
  final Set<String> _autoRegistered = {};

  bool isAutoRegistered(String accountId) =>
      _autoRegistered.contains(accountId);

  Future<void> markAutoRegistered(String accountId) async {
    if (!_autoRegistered.add(accountId)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefAutoRegistered, _autoRegistered.toList());
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    autoRunOnLaunch = prefs.getBool(_prefAutoRun) ?? true;
    sizeLimitBytes =
        prefs.getInt(_prefSizeLimit) ?? 200 * 1024 * 1024;
    _autoRegistered
      ..clear()
      ..addAll(prefs.getStringList(_prefAutoRegistered) ?? const []);
  }

  Future<void> setAutoRunOnLaunch(bool value) async {
    autoRunOnLaunch = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoRun, value);
  }

  Future<void> setSizeLimitBytes(int value) async {
    sizeLimitBytes = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefSizeLimit, value);
    await FollowDb.instance.pruneToSizeLimit(value);
  }

  /// 実行中の進捗。null なら停止中
  final progress = ValueNotifier<FollowJobProgress?>(null);

  /// 走査用 WebView をアプリのルートに置いてほしいか。
  /// これを true にするとどの画面に居ても走査が続く（アプリを開いている限り）。
  /// 常時 WebView を抱えるとメモリを食うので、走査中だけ立てる。
  final hostNeeded = ValueNotifier<bool>(false);

  CaptureCancelToken? _cancelToken;

  /// 連続実行 (runBoth / runDueWork) を止めるフラグ。
  /// 中断したら「次の種別」「次の対象」も走らせない
  bool _chainAborted = false;

  /// 他の処理が x.com の WebView / Cookie を占有している間は true。
  ///
  /// 投稿・ログイン・セッション更新・通知 queryId 取得はいずれも
  /// x.com の Cookie を消して入れ替える。走査 (FollowCaptureWebViewService)
  /// とは Cookie ジャーが共有なので、同時に動かすと互いのセッションを壊す。
  /// 走査は中断しても cursor から再開できるため、常に走査側が道を譲る。
  int _webViewHolders = 0;

  bool get isWebViewBusy => _webViewHolders > 0;

  bool get isRunning => progress.value != null;

  /// x.com の WebView を占有する。走査中なら中断して停止を待つ。
  /// 使い終わったら必ず [releaseWebView] を呼ぶこと。
  Future<void> acquireWebView(String reason) async {
    _webViewHolders++;
    if (!isRunning) return;
    debugPrint('[FollowJob] $reason のため走査を中断します');
    cancel();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (isRunning && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void releaseWebView() {
    if (_webViewHolders > 0) _webViewHolders--;
  }

  void cancel() {
    _chainAborted = true;
    _cancelToken?.cancel();
    // 実際に止まるまで数秒かかることがある。押した瞬間に見た目を変えて
    // 「効いていない」と思われないようにする
    progress.value = progress.value?.copyWith(cancelling: true);
  }

  /// [targetHandle] の一覧を終端まで取得して DB に保存する。
  ///
  /// [resume] に中断済みスナップショットを渡すと、その cursor から再開して
  /// 同じスナップショットに追記する。
  /// followers と following を続けて取得する。
  /// 相互は「最新の完了済みスナップショット同士」で算出するので、
  /// 2 本をひとまとめにする必要はない。順に取るだけ。
  Future<void> runBoth({
    required Account account,
    required String targetHandle,
  }) async {
    final handle = targetHandle.replaceFirst('@', '');
    _chainAborted = false;
    for (final kind in FollowListKind.values) {
      // 中断したのに次の種別が始まると、止めたつもりが止まっていないように見える
      if (_chainAborted) break;
      await run(account: account, targetHandle: handle, kind: kind);
    }
    hostNeeded.value = false;
  }

  /// 期日が来た取得を実行する。アプリ起動時に 1 回呼ぶ。
  ///
  /// キューは持たない。「次に何をすべきか」をそのつど計算するので、
  /// 起動しない日が続いても同じ対象が何度も走ることはない。
  ///
  ///   ① 未完了の走査があれば、まずそれを続きから再開する
  ///   ② 期日が来た (対象 × 種別) を、古い順に 1 回ずつ実行する
  ///   ③ 何もなければ何もしない
  ///
  /// 中断されたらそこで打ち切る（残りは次回起動時に再評価される）。
  Future<void> runDueWork({
    required List<Account> accounts,
    bool force = false,
  }) async {
    if (isRunning || isWebViewBusy) return;
    await loadSettings();
    if (!force && !autoRunOnLaunch) return;
    if (accounts.isEmpty) return;

    _chainAborted = false;
    final db = FollowDb.instance;
    final targets = await db.listTargets();

    Account? accountFor(FollowTarget t) {
      if (accounts.isEmpty) return null;
      return accounts.firstWhere((a) => a.id == t.sessionAccountId,
          orElse: () => accounts.first);
    }

    // ① 未完了の再開を最優先。完了させないまま新しく始めない
    for (final t in targets) {
      if (_chainAborted || isWebViewBusy) return;
      for (final s in await db.resumableFor(t.handle)) {
        final account = accountFor(t);
        if (account == null) continue;
        debugPrint('[FollowJob] 再開: @${t.handle} / ${s.kind}');
        await run(
          account: account,
          targetHandle: t.handle,
          kind: _kindOf(s.kind),
          resume: s,
        );
        if (_chainAborted) return;
      }
    }

    // ② 期日が来たものを古い順に。同じ対象×種別は 1 回だけ。
    //    判定は nextDueAt に一本化する（表示と実行で条件がずれないように）
    final due = <({FollowTarget target, String kind, DateTime dueAt})>[];
    for (final t in targets) {
      for (final kind in const ['followers', 'following']) {
        final dueAt = await nextDueAt(t, kind);
        if (dueAt == null || dueAt.isAfter(DateTime.now())) continue;
        due.add((target: t, kind: kind, dueAt: dueAt));
      }
    }
    due.sort((a, b) => a.dueAt.compareTo(b.dueAt));

    for (final item in due) {
      if (_chainAborted || isWebViewBusy) return;
      final account = accountFor(item.target);
      if (account == null) continue;
      debugPrint('[FollowJob] スケジュール実行: '
          '@${item.target.handle} / ${item.kind}');
      await run(
        account: account,
        targetHandle: item.target.handle,
        kind: _kindOf(item.kind),
      );
    }

    await FollowDb.instance.pruneToSizeLimit(sizeLimitBytes);
  }

  /// 期日どうしの間隔が詰まりすぎないための下限。
  /// 23:50 に終わって 00:10 に起動、のような直後の再実行を防ぐ。
  static const _minimumGap = Duration(hours: 12);

  /// 次にその (対象 × 種別) が実行される予定時刻。スケジュール無しなら null。
  ///
  /// **日付を基準にする**のが要点。「前回の完了時刻 + N日」にすると、
  /// 実行が遅れたぶんだけ基準が後ろにずれ、毎回少しずつ時刻が動いてしまう。
  /// 時刻成分を捨てれば「1日おき = 日付が変わったら次に開いたとき」になり、
  /// ズレが蓄積しない。
  static Future<DateTime?> nextDueAt(FollowTarget target, String kind) async {
    final interval = target.intervalFor(kind);
    if (interval <= 0) return null;
    final last = await FollowDb.instance.latestCompleted(target.handle, kind);
    if (last == null) return DateTime.now();

    final base = last.completedAt ?? last.startedAt;
    final byDate = DateTime(base.year, base.month, base.day)
        .add(Duration(days: interval));
    final earliest = base.add(_minimumGap);
    return byDate.isAfter(earliest) ? byDate : earliest;
  }

  static FollowListKind _kindOf(String kind) => kind == 'followers'
      ? FollowListKind.followers
      : FollowListKind.following;

  Future<void> _recordExpectedTotal(
      Account account, String handle, FollowListKind kind, int snapshotId) async {
    try {
      final profile = await XApiService.instance
          .getUserProfile(account.xCredentials, handle);
      final legacy = profile?['legacy'] as Map<String, dynamic>?;
      final key = kind == FollowListKind.followers
          ? 'followers_count'
          : 'friends_count';
      final expected = legacy == null ? null : legacy[key];
      if (expected is int) {
        await FollowDb.instance.setTotalExpected(snapshotId, expected);
        debugPrint('[FollowJob] 想定件数 $expected (@$handle / ${kind.name})');
      }
    } catch (e) {
      debugPrint('[FollowJob] 想定件数の取得に失敗: $e');
    }
  }

  Future<FollowSnapshot?> run({
    required Account account,
    required String targetHandle,
    required FollowListKind kind,
    FollowSnapshot? resume,
    int? runId,
  }) async {
    if (isRunning) throw StateError('別の走査が実行中です');
    if (isWebViewBusy) throw StateError('他の処理が WebView を使用中です');

    final db = FollowDb.instance;
    final handle = targetHandle.replaceFirst('@', '');
    final snapshotId = resume?.id ??
        await db.startSnapshot(
          targetHandle: handle,
          kind: kind.name,
          sessionAccountId: account.id,
          runId: runId,
        );

    // プロフィール上の件数を「想定件数」として控える。
    // 取りこぼしがあっても気づけないのが一番まずいので、照合材料を残す。
    if (resume == null) {
      await _recordExpectedTotal(account, handle, kind, snapshotId);
    }

    // ルートにホストを立ててから走らせる（画面を移動しても継続させるため）
    hostNeeded.value = true;
    await FollowCaptureWebViewService.instance.waitForHost();

    _cancelToken = CaptureCancelToken();
    progress.value = FollowJobProgress(
      snapshotId: snapshotId,
      targetHandle: handle,
      kind: kind,
      collected: resume?.collectedCount ?? 0,
      round: 0,
      startedAt: resume?.startedAt ?? DateTime.now(),
    );

    final service = FollowCaptureWebViewService.instance;
    final pool = AccountPool([account.id], cooldown: _accountCooldown);
    final engine = FollowCaptureEngine(fetchPage: service.fetchPage);

    var lastCursor = resume?.cursor;

    try {
      final result = await engine.capture(
        targetHandle: handle,
        kind: kind,
        pool: pool,
        accountOf: (_) => account,
        startCursor: resume?.cursor,
        cancelToken: _cancelToken,
        onBatch: (users, cursor) async {
          lastCursor = cursor;
          await db.addBatch(
              snapshotId: snapshotId, users: users, cursor: cursor);
        },
        onProgress: (p) {
          progress.value = progress.value?.copyWith(
            collected: p.collected + (resume?.collectedCount ?? 0),
            round: p.round,
            rateLimit: p.rateLimit,
            clearWaiting: true,
          );
        },
        onWaiting: (w) {
          progress.value = w == null
              ? progress.value?.copyWith(clearWaiting: true)
              : progress.value?.copyWith(
                  waitingReason: w.reason,
                  waitingUntil: w.startedAt.add(w.total),
                );
        },
      );

      await db.finishSnapshot(
        snapshotId: snapshotId,
        completed: result.completed,
        reason: result.reason.name,
        cursor: result.completed ? null : result.cursor,
      );
      debugPrint('[FollowJob] 完了: ${result.reason.name} '
          '${result.totalUsers}件 completed=${result.completed}');
      return db.getSnapshot(snapshotId);
    } catch (e, st) {
      debugPrint('[FollowJob] 例外: $e\n$st');
      await db.finishSnapshot(
        snapshotId: snapshotId,
        completed: false,
        reason: 'error: $e',
        cursor: lastCursor,
      );
      rethrow;
    } finally {
      _cancelToken = null;
      progress.value = null;
      await service.reset();
      // runBoth の途中では畳まない（次の種別で再利用する）
      if (runId == null) hostNeeded.value = false;
    }
  }
}
