import '../utils/account_date.dart';

/// 作成日の 1 区切り（1 年、または 1 か月）
class AgeBucket {
  AgeBucket({required this.year, this.month});

  final int year;

  /// 月ごとの区切りなら 1〜12。年ごとなら null
  final int? month;
  final List<String> restIds = [];

  int get count => restIds.length;

  /// 月ごとで目立って多いか。[AccountAgeStats] が立てる
  bool spike = false;

  String get label => month == null ? '$year年' : '$year/$month';

  DateTime get start => DateTime(year, month ?? 1);
}

/// 一覧の中のアカウント作成日の分布。
///
/// 捨てアカウントやボットはまとめて作られるので、ある月だけ作成が
/// 固まっていると目に付く。年ごとの山と、直近の月ごとの山を出し、
/// 月ごとは他の月に比べて多すぎるところに印を付ける
class AccountAgeStats {
  AccountAgeStats._({
    required this.total,
    required this.unknown,
    required this.years,
    required this.months,
    required this.last30Days,
    required this.lastYear,
  });

  /// 月ごとに見る範囲（直近 N か月）
  static const monthsShown = 36;

  /// この倍数を超えたら「目立って多い」。少なすぎる月で騒がないよう下限も置く
  static const spikeFactor = 3;
  static const spikeMinCount = 5;

  final int total;

  /// 作成日が読めなかった人数
  final int unknown;

  /// 古い年から順
  final List<AgeBucket> years;

  /// 新しい月から順（直近 [monthsShown] か月）。0 人の月も入る
  final List<AgeBucket> months;

  final List<String> last30Days;
  final List<String> lastYear;

  factory AccountAgeStats.from(
    Iterable<({String restId, String createdAt})> rows, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final yearMap = <int, AgeBucket>{};
    final monthMap = <(int, int), AgeBucket>{};
    final last30 = <String>[];
    final lastY = <String>[];
    var total = 0;
    var unknown = 0;

    final monthFloor = DateTime(today.year, today.month - (monthsShown - 1));

    for (final r in rows) {
      total++;
      final dt = parseAccountCreatedAt(r.createdAt)?.toLocal();
      if (dt == null) {
        unknown++;
        continue;
      }
      (yearMap[dt.year] ??= AgeBucket(year: dt.year)).restIds.add(r.restId);
      if (!dt.isBefore(monthFloor)) {
        (monthMap[(dt.year, dt.month)] ??=
                AgeBucket(year: dt.year, month: dt.month))
            .restIds
            .add(r.restId);
      }
      final age = today.difference(dt);
      if (age.inDays < 30) last30.add(r.restId);
      if (age.inDays < 365) lastY.add(r.restId);
    }

    final years = yearMap.values.toList()
      ..sort((a, b) => a.year.compareTo(b.year));

    // 0 人の月も並べる。飛ばすと「その月は無かった」のか分からない
    final months = <AgeBucket>[];
    for (var i = 0; i < monthsShown; i++) {
      final d = DateTime(today.year, today.month - i);
      months.add(monthMap[(d.year, d.month)] ??
          AgeBucket(year: d.year, month: d.month));
    }
    _markSpikes(months);

    return AccountAgeStats._(
      total: total,
      unknown: unknown,
      years: years,
      months: months,
      last30Days: last30,
      lastYear: lastY,
    );
  }

  /// 人が居る月の中央値に比べて [spikeFactor] 倍を超える月に印を付ける
  static void _markSpikes(List<AgeBucket> months) {
    final counts = months.map((m) => m.count).where((c) => c > 0).toList()
      ..sort();
    if (counts.length < 3) return;
    final median = counts[counts.length ~/ 2];
    final threshold = median * spikeFactor;
    for (final m in months) {
      m.spike = m.count >= spikeMinCount && m.count > threshold;
    }
  }

  /// 一番人数の多い年
  AgeBucket? get peakYear => years.isEmpty
      ? null
      : years.reduce((a, b) => b.count > a.count ? b : a);

  bool get hasSpike => months.any((m) => m.spike);
}
