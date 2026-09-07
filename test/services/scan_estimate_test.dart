import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/scan_estimate.dart';

void main() {
  group('所要時間の計算', () {
    test('件数とレートから時間を出す', () {
      // 3000件を1分1500件で取れば2分
      const e = ScanEstimate(items: 3000, ratePerMinute: 1500);
      expect(e.duration, const Duration(minutes: 2));
    });

    test('件数が分からなければ 0', () {
      const e = ScanEstimate(items: 0, ratePerMinute: 1500);
      expect(e.duration, Duration.zero);
      expect(e.label, '—');
    });

    // 実績が取れないうちにゼロ割りしない
    test('レートが 0 でも落ちない', () {
      const e = ScanEstimate(items: 1000, ratePerMinute: 0);
      expect(e.duration, Duration.zero);
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
