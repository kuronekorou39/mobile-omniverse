import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/account_age_stats.dart';

void main() {
  final now = DateTime(2026, 10, 24, 12);

  String x(DateTime d) {
    const mon = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final u = d.toUtc();
    return 'Thu ${mon[u.month - 1]} ${u.day.toString().padLeft(2, '0')} '
        '${u.hour.toString().padLeft(2, '0')}:00:00 +0000 ${u.year}';
  }

  ({String restId, String createdAt}) row(String id, DateTime d) =>
      (restId: id, createdAt: x(d));

  test('年ごとに数え、古い年から並ぶ', () {
    final s = AccountAgeStats.from([
      row('1', DateTime(2020, 5, 1)),
      row('2', DateTime(2023, 1, 1)),
      row('3', DateTime(2023, 6, 1)),
    ], now: now);
    expect(s.years.map((y) => y.year), [2020, 2023]);
    expect(s.years.last.count, 2);
    expect(s.peakYear!.year, 2023);
  });

  test('直近 36 か月は 0 人の月も含めて新しい順に並ぶ', () {
    final s = AccountAgeStats.from([
      row('1', DateTime(2026, 9, 3)),
    ], now: now);
    expect(s.months.length, AccountAgeStats.monthsShown);
    expect(s.months.first.label, '2026/10');
    expect(s.months[1].label, '2026/9');
    expect(s.months[1].count, 1);
    expect(s.months.last.label, '2023/11');
  });

  test('読めない作成日は不明として数える', () {
    final s = AccountAgeStats.from([
      (restId: '1', createdAt: ''),
      row('2', DateTime(2024, 1, 1)),
    ], now: now);
    expect(s.total, 2);
    expect(s.unknown, 1);
  });

  test('直近 30 日と 1 年を分ける', () {
    final s = AccountAgeStats.from([
      row('a', now.subtract(const Duration(days: 3))),
      row('b', now.subtract(const Duration(days: 100))),
      row('c', now.subtract(const Duration(days: 400))),
    ], now: now);
    expect(s.last30Days, ['a']);
    expect(s.lastYear, ['a', 'b']);
  });

  test('他の月の 3 倍を超えて 5 人以上の月に印が付く', () {
    final rows = <({String restId, String createdAt})>[];
    // ふだんは月 1 人
    for (var i = 1; i <= 6; i++) {
      rows.add(row('m$i', DateTime(2026, i, 10)));
    }
    // 8 月だけ 6 人
    for (var i = 0; i < 6; i++) {
      rows.add(row('s$i', DateTime(2026, 8, 1 + i)));
    }
    final s = AccountAgeStats.from(rows, now: now);
    final aug = s.months.firstWhere((m) => m.label == '2026/8');
    expect(aug.spike, isTrue);
    expect(s.months.where((m) => m.spike).length, 1);
    expect(s.hasSpike, isTrue);
  });

  test('人数が少ない月は多めでも騒がない', () {
    final s = AccountAgeStats.from([
      row('1', DateTime(2026, 1, 1)),
      row('2', DateTime(2026, 2, 1)),
      row('3', DateTime(2026, 3, 1)),
      row('4', DateTime(2026, 8, 1)),
      row('5', DateTime(2026, 8, 2)),
      row('6', DateTime(2026, 8, 3)),
      row('7', DateTime(2026, 8, 4)),
    ], now: now);
    // 4 人は 3 倍を超えるが 5 人未満
    expect(s.hasSpike, isFalse);
  });
}
