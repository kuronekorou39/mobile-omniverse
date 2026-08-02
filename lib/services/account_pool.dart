import 'dart:math';

import '../models/x_rate_limit.dart';

/// 走査に使う X アカウントを、アカウント単位のクールダウンで回すプール
///
/// Follow-Capture-Tool の tokenpool.js を、キーを
/// `x-client-transaction-id` → アカウント ID に置き換えて移植したもの。
/// X のレート制限はアカウント単位でカウントされるため、N アカウントを
/// ローテーションすると全体の送信間隔を cooldown/N まで詰められる。
///
/// (txId 側の再利用制限は XApiService が毎リクエストで新しい値を
///  生成しているため、ここでは扱わない)
class AccountPool {
  AccountPool(
    List<String> accountIds, {
    this.cooldown = defaultCooldown,
    int? consecutiveFailureLimit,
  }) : consecutiveFailureLimit =
            consecutiveFailureLimit ?? accountIds.length + 1 {
    for (final id in accountIds) {
      if (id.isNotEmpty) _lastUsedAt[id] = null;
    }
  }

  /// Followers の実測値。Following はもっと短くできる
  static const defaultCooldown = Duration(seconds: 60);

  // --- 適応スロットルの閾値 (paginator.js calcDynamicInterval 相当) ---

  /// これを下回ったら reset まで待つ
  static const criticalRemainingRatio = 0.05;

  /// これを下回ったら減速する
  static const slowdownRemainingRatio = 0.15;

  /// 減速時の倍率と下限
  static const slowdownFactor = 3;
  static const slowdownFloor = Duration(seconds: 6);

  /// 残量わずかで reset 時刻が不明なときの倍率と下限
  static const criticalFactor = 30;
  static const criticalFloor = Duration(seconds: 30);

  /// reset 直後を叩かないための上乗せ
  static const resetMargin = Duration(seconds: 5);

  final Duration cooldown;

  /// 連続失敗がこの回数に達したら circuit break。
  ///
  /// 既定 (アカウント数 + 1) は失敗ごとに 1 件ずつ減る以上到達しないので、
  /// 実質「全アカウントが失効するまで粘る」= 打ち切りなしの意味になる。
  /// systemic な失敗で全アカウントを焼きたくない場合はこれより小さく指定する。
  final int consecutiveFailureLimit;

  /// null = まだ一度も使っていない (最も古いものとして扱う)
  final Map<String, DateTime?> _lastUsedAt = {};
  final Map<String, XRateLimit> _rateLimits = {};

  int _consecutiveFailures = 0;

  int get size => _lastUsedAt.length;
  bool get isEmpty => _lastUsedAt.isEmpty;
  List<String> get accountIds => _lastUsedAt.keys.toList(growable: false);
  int get consecutiveFailures => _consecutiveFailures;
  bool get shouldCircuitBreak =>
      _consecutiveFailures >= consecutiveFailureLimit;

  /// cooldown 明けのうち「最も古くに使ったもの」を返す (連続使用を避ける)。
  /// 全員 cooldown 中なら null
  String? pick({DateTime? now}) {
    final at = now ?? DateTime.now();
    String? best;
    DateTime? bestLastUsed;

    for (final entry in _lastUsedAt.entries) {
      final lastUsed = entry.value;
      if (lastUsed != null && at.difference(lastUsed) < cooldown) continue;
      // 未使用 (null) は無条件で最優先
      if (lastUsed == null) return entry.key;
      if (bestLastUsed == null || lastUsed.isBefore(bestLastUsed)) {
        best = entry.key;
        bestLastUsed = lastUsed;
      }
    }
    return best;
  }

  /// 全員 cooldown 中のときの最短待ち時間
  Duration timeUntilNext({DateTime? now}) {
    if (_lastUsedAt.isEmpty) return Duration.zero;
    final at = now ?? DateTime.now();
    var minWait = cooldown;
    for (final lastUsed in _lastUsedAt.values) {
      if (lastUsed == null) return Duration.zero;
      final elapsed = at.difference(lastUsed);
      final wait = cooldown - elapsed;
      if (wait.isNegative) return Duration.zero;
      if (wait < minWait) minWait = wait;
    }
    return minWait;
  }

  void markUsed(String accountId, {DateTime? at}) {
    if (_lastUsedAt.containsKey(accountId)) {
      _lastUsedAt[accountId] = at ?? DateTime.now();
    }
  }

  /// 成功応答で連続失敗カウンタをリセット
  void markSuccess() => _consecutiveFailures = 0;

  /// 失効 (401/403 や不正応答) → プールから外して連続失敗を数える
  void markFailed(String accountId) {
    _lastUsedAt.remove(accountId);
    _rateLimits.remove(accountId);
    _consecutiveFailures++;
  }

  void updateRateLimit(String accountId, XRateLimit? rateLimit) {
    if (rateLimit == null) return;
    if (!_lastUsedAt.containsKey(accountId)) return;
    _rateLimits[accountId] = rateLimit;
  }

  XRateLimit? rateLimitOf(String accountId) => _rateLimits[accountId];

  /// プール全体の基準送信間隔。アカウント数で割った分だけ詰められる
  Duration get baseInterval => Duration(
      milliseconds: (cooldown.inMilliseconds / max(1, size)).ceil());

  /// 残量に応じて基準間隔を延ばす。
  /// 429 を踏んでから待つのではなく、踏む前に減速するのが目的。
  Duration dynamicInterval(String accountId, {DateTime? now}) {
    final base = baseInterval;
    final rl = _rateLimits[accountId];
    final ratio = rl?.remainingRatio;
    if (rl == null || ratio == null) return base;

    if (ratio < criticalRemainingRatio || (rl.remaining ?? 0) <= 1) {
      final untilReset = rl.untilReset(now: now);
      if (untilReset != null) {
        return _atLeast(untilReset + resetMargin, criticalFloor);
      }
      return _atLeast(base * criticalFactor, criticalFloor);
    }
    if (ratio < slowdownRemainingRatio) {
      return _atLeast(base * slowdownFactor, slowdownFloor);
    }
    return base;
  }

  /// UI 表示用のスナップショット
  List<({String accountId, Duration cooldownRemaining, XRateLimit? rateLimit})>
      snapshot({DateTime? now}) {
    final at = now ?? DateTime.now();
    return [
      for (final entry in _lastUsedAt.entries)
        (
          accountId: entry.key,
          cooldownRemaining: entry.value == null
              ? Duration.zero
              : _atLeast(cooldown - at.difference(entry.value!), Duration.zero),
          rateLimit: _rateLimits[entry.key],
        ),
    ];
  }

  static Duration _atLeast(Duration value, Duration floor) =>
      value < floor ? floor : value;
}
