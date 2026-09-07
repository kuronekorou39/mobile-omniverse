import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/scan_estimate.dart';

void main() {
  group('速さの理論値', () {
    // 2 秒ごとに 50 件 → 毎分 1500 件
    test('送信間隔と 1 ページの件数から出す', () {
      expect(ScanEstimate.itemsPerPage, 50);
      expect(ScanEstimate.pageIntervalSeconds, 2);
      expect(ScanEstimate.ratePerMinute, 1500);
    });
  });

  group('所要時間の計算', () {
    test('件数を理論値で割る', () {
      // 3000件 ÷ 毎分1500件 = 2分
      expect(const ScanEstimate(items: 3000).duration,
          const Duration(minutes: 2));
      // 90000件 = 1時間
      expect(const ScanEstimate(items: 90000).duration,
          const Duration(hours: 1));
    });

    test('件数が分からなければ 0', () {
      const e = ScanEstimate(items: 0);
      expect(e.duration, Duration.zero);
      expect(e.label, '—');
    });
  });

  group('表示の丸め', () {
    String label(Duration d) => ScanEstimate.roughLabel(d);

    test('1分未満', () {
      expect(label(const Duration(seconds: 30)), '1分未満');
    });

    test('1時間未満は分で出す', () {
      expect(label(const Duration(minutes: 40)), '約40分');
    });

    test('3時間未満は10分単位まで', () {
      expect(label(const Duration(hours: 2, minutes: 35)), '約2時間30分');
    });

    // 見積もりは前後するので、長い時間で分まで出しても当てにならない
    test('3時間以上は時間だけ', () {
      expect(label(const Duration(hours: 5, minutes: 40)), '約5時間');
    });

    test('端数が小さければ時間だけ', () {
      expect(label(const Duration(hours: 2, minutes: 5)), '約2時間');
    });

    test('1日を超えたら日で出す', () {
      expect(label(const Duration(days: 2, hours: 1)), '約2日');
      expect(label(const Duration(days: 1, hours: 8)), '約1日8時間');
    });
  });
}
