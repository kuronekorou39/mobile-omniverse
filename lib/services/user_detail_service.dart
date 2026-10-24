import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import 'debug_log_service.dart';
import 'follow_db.dart';
import 'x_api_service.dart';

/// 実行中の取得の様子。UI はこれを見て描く
class UserDetailProgress {
  const UserDetailProgress({
    required this.targetHandle,
    required this.origin,
    required this.total,
    required this.wantBirthday,
    required this.wantLastPost,
    this.done = 0,
    this.failed = 0,
    this.currentHandle,
    this.waitingUntil,
    this.waitingReason,
    this.cancelling = false,
  });

  final String targetHandle;

  /// 'following' / 'followers' / 'mutual'
  final String origin;
  final int total;
  final int done;

  /// 取れなかった人数（鍵、停止、通信の失敗など）
  final int failed;
  final bool wantBirthday;
  final bool wantLastPost;
  final String? currentHandle;

  /// X の制限で待っているあいだ、いつまで待つかと理由
  final DateTime? waitingUntil;
  final String? waitingReason;
  final bool cancelling;

  UserDetailProgress copyWith({
    int? done,
    int? failed,
    String? currentHandle,
    DateTime? waitingUntil,
    String? waitingReason,
    bool clearWaiting = false,
    bool? cancelling,
  }) =>
      UserDetailProgress(
        targetHandle: targetHandle,
        origin: origin,
        total: total,
        wantBirthday: wantBirthday,
        wantLastPost: wantLastPost,
        done: done ?? this.done,
        failed: failed ?? this.failed,
        currentHandle: currentHandle ?? this.currentHandle,
        waitingUntil: clearWaiting ? null : (waitingUntil ?? this.waitingUntil),
        waitingReason:
            clearWaiting ? null : (waitingReason ?? this.waitingReason),
        cancelling: cancelling ?? this.cancelling,
      );
}

/// 一覧の API では取れない情報を、1 人ずつプロフィールと投稿を見て集める。
///
/// 誕生日はプロフィール（UserByScreenName）、最近の投稿日は投稿一覧
/// （UserTweets）の 1 ページ目から読む。どちらも 1 人 1 回の通信なので、
/// 数千人の一覧なら数時間、数万人なら使えない。小さな一覧向け。
///
/// 走らせるたびに「まだ調べていない人」「古くなった人」だけを拾うので、
/// 途中で止めても次に始めれば続きになる。記録は [FollowDb] の user_details
class UserDetailService {
  UserDetailService._();
  static final instance = UserDetailService._();

  /// 1 通信ごとの間隔。X の制限は 15 分窓なので、短くしても 429 で止まるだけ。
  /// 試験では 0 にする
  Duration interval = defaultInterval;
  static const defaultInterval = Duration(seconds: 2);

  /// これより前に調べた人は取り直す
  static const freshFor = Duration(days: 30);

  /// 投稿一覧から読む件数。固定投稿やリポストが混ざるので少し多めに
  static const postsPerUser = 20;

  final progress = ValueNotifier<UserDetailProgress?>(null);
  bool _cancelled = false;

  /// 通信の入口。試験ではここを差し替える（XApiService は作れないので関数で）
  @visibleForTesting
  Future<Map<String, dynamic>?> Function(XCredentials creds, String screenName)
      fetchProfile = (creds, screenName) =>
          XApiService.instance.getUserResult(creds, screenName);

  @visibleForTesting
  Future<({List<Post> posts, String? cursor})> Function(
          XCredentials creds, String restId, int count) fetchTimeline =
      (creds, restId, count) =>
          XApiService.instance.getUserTimeline(creds, restId, count: count);

  bool get isRunning => progress.value != null;

  void cancel() {
    _cancelled = true;
    progress.value = progress.value?.copyWith(cancelling: true);
  }

  /// 起点の一覧の人たちを調べる。調べる人が居なければ 0 を返す。
  ///
  /// [refresh] なら調べた時期を問わず全員を取り直す
  Future<int> start({
    required Account account,
    required SnsService service,
    required String handle,
    required String origin,
    required bool wantBirthday,
    required bool wantLastPost,
    bool refresh = false,
  }) async {
    if (isRunning) throw StateError('別の取得が実行中です');
    if (service != SnsService.x || account.service != SnsService.x) {
      throw StateError('詳しい情報の取得は X のみ対応しています');
    }
    if (!wantBirthday && !wantLastPost) return 0;

    final db = FollowDb.instance;
    final members = FollowDb.memberSetFor(
      origin,
      followers: await db.latestCompleted(service, handle, 'followers'),
      following: await db.latestCompleted(service, handle, 'following'),
    );
    if (members == null) return 0;

    final freshAfter = refresh
        ? DateTime.now().millisecondsSinceEpoch + 1
        : DateTime.now().subtract(freshFor).millisecondsSinceEpoch;
    final targets = await db.detailCandidates(
      members,
      wantBirthday: wantBirthday,
      wantLastPost: wantLastPost,
      freshAfterMs: freshAfter,
    );
    if (targets.isEmpty) return 0;

    _cancelled = false;
    progress.value = UserDetailProgress(
      targetHandle: handle,
      origin: origin,
      total: targets.length,
      wantBirthday: wantBirthday,
      wantLastPost: wantLastPost,
    );
    DebugLogService.instance.log('UserDetail',
        '取得を開始: @$handle の$origin ${targets.length}人 '
        '(誕生日=$wantBirthday 投稿=$wantLastPost)');

    final creds = account.xCredentials;
    var done = 0;
    var failed = 0;
    try {
      for (final t in targets) {
        if (_cancelled) break;
        progress.value = progress.value?.copyWith(currentHandle: t.screenName);
        final ok = await _fetchOne(creds, t.restId, t.screenName,
            wantBirthday: wantBirthday, wantLastPost: wantLastPost);
        if (ok == null) break; // 認証切れなどで続けられない
        done++;
        if (!ok) failed++;
        progress.value = progress.value?.copyWith(done: done, failed: failed);
        if (_cancelled) break;
        await _sleep(interval);
      }
    } finally {
      progress.value = null;
      DebugLogService.instance
          .log('UserDetail', '取得を終了: $done/${targets.length}人 失敗 $failed');
    }
    return targets.length;
  }

  /// 1 人ぶん。true=取れた false=取れなかった null=続けられない
  Future<bool?> _fetchOne(
    XCredentials creds,
    String restId,
    String screenName, {
    required bool wantBirthday,
    required bool wantLastPost,
  }) async {
    final db = FollowDb.instance;
    var failed = false;

    if (wantBirthday) {
      final r = await _withRateLimitWait(
          () => fetchProfile(creds, screenName), 'UserByScreenName');
      if (r.abort) return null;
      if (r.error != null) {
        failed = true;
        await db.upsertUserDetail(restId,
            profile: (month: null, day: null, year: null), error: r.error);
      } else {
        await db.upsertUserDetail(restId,
            profile: parseBirthdate(r.value) ??
                (month: null, day: null, year: null),
            clearError: true);
      }
      if (wantLastPost && !_cancelled) await _sleep(interval);
    }

    if (wantLastPost && !_cancelled) {
      final r = await _withRateLimitWait(
          () => fetchTimeline(creds, restId, postsPerUser), 'UserTweets');
      if (r.abort) return null;
      if (r.error != null) {
        failed = true;
        await db.upsertUserDetail(restId,
            posts: (last: null, lastOwn: null), error: r.error);
      } else {
        await db.upsertUserDetail(restId,
            posts: summarizePosts(r.value!.posts), clearError: true);
      }
    }
    return !failed;
  }

  /// 429 なら教えられた時間だけ待って、同じ人をもう一度。
  /// 認証切れは続けても全員失敗するので止める
  Future<({T? value, String? error, bool abort})> _withRateLimitWait<T>(
      Future<T> Function() request, String operation) async {
    while (true) {
      if (_cancelled) return (value: null, error: '中断', abort: true);
      try {
        return (value: await request(), error: null, abort: false);
      } on XRateLimitException catch (e) {
        final until = DateTime.now().add(e.retryAfter);
        progress.value = progress.value?.copyWith(
            waitingUntil: until, waitingReason: 'X の制限（$operation）');
        DebugLogService.instance.log('UserDetail',
            '$operation が制限中。${e.retryAfter.inSeconds}秒待つ');
        await _sleep(e.retryAfter);
        progress.value = progress.value?.copyWith(clearWaiting: true);
      } on XAuthException catch (e) {
        DebugLogService.instance.log('UserDetail', '認証に失敗。止める: $e');
        return (value: null, error: '認証に失敗', abort: true);
      } catch (e) {
        return (value: null, error: _shortError(e), abort: false);
      }
    }
  }

  /// 鍵や停止は X が 200 で中身なし、または例外で返す。長い文は出さない
  static String _shortError(Object e) {
    final s = '$e';
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }

  /// 中断が押されたらすぐ抜けられるよう、短く刻んで寝る
  Future<void> _sleep(Duration d) async {
    final end = DateTime.now().add(d);
    while (!_cancelled && DateTime.now().isBefore(end)) {
      final left = end.difference(DateTime.now());
      await Future.delayed(left < const Duration(milliseconds: 500)
          ? left
          : const Duration(milliseconds: 500));
    }
  }

  /// UserByScreenName の result から誕生日を読む。
  ///
  /// `legacy_extended_profile.birthdate` に day / month / year が入る。
  /// 年は本人が別に隠せるので無いことがある。項目ごと無ければ非公開か未設定
  static ({int? month, int? day, int? year})? parseBirthdate(
      Map<String, dynamic>? userResult) {
    if (userResult == null) return null;
    final ext = userResult['legacy_extended_profile'];
    if (ext is! Map) return null;
    final b = ext['birthdate'];
    if (b is! Map) return null;
    final month = _int(b['month']);
    final day = _int(b['day']);
    if (month == null || day == null) return null;
    return (month: month, day: day, year: _int(b['year']));
  }

  static int? _int(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));

  /// 投稿一覧から「最近の投稿」と「最近の自分の投稿」を拾う。
  /// 固定投稿は一覧の先頭に古いものが来るので、新しさで選ぶ
  static ({DateTime? last, DateTime? lastOwn}) summarizePosts(List<Post> posts) {
    DateTime? last;
    DateTime? lastOwn;
    for (final p in posts) {
      if (last == null || p.timestamp.isAfter(last)) last = p.timestamp;
      if (!p.isRetweet && (lastOwn == null || p.timestamp.isAfter(lastOwn))) {
        lastOwn = p.timestamp;
      }
    }
    return (last: last, lastOwn: lastOwn);
  }
}
