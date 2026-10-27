import 'dart:async';

import 'android_background.dart';
import 'block_scan_service.dart';
import 'debug_log_service.dart';
import 'fetch_jobs.dart';
import 'follow_capture_job_service.dart';
import 'user_detail_service.dart';

/// 取得が走っている間だけ、Android の前面サービス（通知）を出しておく。
///
/// 裏に回ったアプリは凍結され、画面を消すと CPU も眠るので、通知なしでは
/// 取得が進まない。始まったら出し、終わったら消す。
class BackgroundJobKeeper {
  BackgroundJobKeeper._();
  static final instance = BackgroundJobKeeper._();

  /// 終わってから通知を消すまでの猶予。
  ///
  /// フォローとフォロワーを続けて取るときなど、1 本目と 2 本目の間に
  /// 一瞬だけ「何も走っていない」状態になる。そこで消すと、裏に居る間は
  /// 前面サービスを始め直せない（Android 12 以降の決まり）ので、続きが凍る。
  static const stopGrace = Duration(seconds: 10);

  /// 通知を書き換える間隔の下限。速すぎる更新は Android に間引かれる
  static const updateInterval = Duration(seconds: 5);

  bool _started = false;
  bool _askedPermission = false;
  Timer? _stopTimer;
  Timer? _updateTimer;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  void init() {
    final jobs = FetchJobs.instance;
    jobs.current.addListener(_onChanged);
    AndroidBackground.setCancelHandler(_cancelCurrent);
    _onChanged();
  }

  void _onChanged() {
    final c = FetchJobs.instance.current.value;
    if (c == null) {
      _updateTimer?.cancel();
      _updateTimer = null;
      _stopTimer ??= Timer(stopGrace, _stop);
      return;
    }
    _stopTimer?.cancel();
    _stopTimer = null;
    if (!_started) {
      _start(c);
      return;
    }
    // 進み具合は 2 秒ごとに変わる。通知は間隔を空けて最後の値を出す
    final wait = updateInterval - DateTime.now().difference(_lastUpdate);
    if (wait <= Duration.zero) {
      _push();
    } else {
      _updateTimer ??= Timer(wait, _push);
    }
  }

  Future<void> _start(RunningFetch c) async {
    _started = true;
    _lastUpdate = DateTime.now();
    if (!_askedPermission) {
      _askedPermission = true;
      await AndroidBackground.requestNotificationPermission();
    }
    final ok = await AndroidBackground.start(
        title: c.title, text: c.detail, done: c.done ?? 0, total: c.total ?? 0);
    DebugLogService.instance
        .log('BackgroundJob', '前面サービスを開始: ${ok ? '成功' : '失敗'}');
    // 裏に居て始められなかったら、次に変化があったときにもう一度試す
    if (!ok) _started = false;
  }

  void _push() {
    _updateTimer = null;
    final c = FetchJobs.instance.current.value;
    if (c == null) return;
    _lastUpdate = DateTime.now();
    AndroidBackground.update(
        title: c.title, text: c.detail, done: c.done ?? 0, total: c.total ?? 0);
  }

  Future<void> _stop() async {
    _stopTimer = null;
    if (!_started) return;
    _started = false;
    await AndroidBackground.stop();
    DebugLogService.instance.log('BackgroundJob', '前面サービスを終了');
  }

  /// 通知の「中断」。走っているものを止める（続きから再開できる）
  void _cancelCurrent() {
    switch (FetchJobs.instance.current.value?.kind) {
      case FetchJobKind.blockScan:
        BlockScanService.instance.cancel();
      case FetchJobKind.userDetail:
        UserDetailService.instance.cancel();
      case FetchJobKind.followCapture:
        FollowCaptureJobService.instance.cancel();
      case null:
        break;
    }
  }
}
