/// X API の `x-rate-limit-*` レスポンスヘッダーを表す値
///
/// 429 を踏んでから待つのではなく、残量を見て**踏む前に減速する**ために使う。
/// レート制限はアカウント単位でカウントされるため、アカウントごとに保持する。
class XRateLimit {
  const XRateLimit({this.limit, this.remaining, this.resetAt});

  final int? limit;
  final int? remaining;
  final DateTime? resetAt;

  /// 残量の比率 (limit か remaining が不明なら null)
  double? get remainingRatio {
    final l = limit;
    final r = remaining;
    if (l == null || r == null || l <= 0) return null;
    return r / l;
  }

  /// reset までの残り時間 (すでに過ぎている / 不明なら null)
  Duration? untilReset({DateTime? now}) {
    final reset = resetAt;
    if (reset == null) return null;
    final diff = reset.difference(now ?? DateTime.now());
    return diff.isNegative ? null : diff;
  }

  /// レスポンスヘッダーから抽出。3 つとも無ければ null
  static XRateLimit? fromHeaders(Map<String, String> headers) {
    int? pick(String name) {
      final raw = headers[name] ?? headers[name.toLowerCase()];
      return raw == null ? null : int.tryParse(raw.trim());
    }

    final limit = pick('x-rate-limit-limit');
    final remaining = pick('x-rate-limit-remaining');
    final resetSec = pick('x-rate-limit-reset');
    if (limit == null && remaining == null && resetSec == null) return null;

    return XRateLimit(
      limit: limit,
      remaining: remaining,
      resetAt: resetSec == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(resetSec * 1000),
    );
  }

  @override
  String toString() =>
      'XRateLimit($remaining/$limit, reset=${resetAt?.toIso8601String()})';
}
