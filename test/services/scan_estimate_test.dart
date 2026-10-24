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

  group('保存容量の目安', () {
    const mb = 1024 * 1024;

    test('延べ 1 件の単価は実測の行と、重複を見込んだ相手のぶん', () {
      expect(ScanEstimate.bytesPerItem,
          closeTo(136 + 266 * 0.3, 0.001));
    });

    test('延べ件数に単価を掛ける', () {
      final e = const ScanEstimate(items: 13000000);
      expect(e.storageBytes, (13000000 * ScanEstimate.bytesPerItem).round());
      // 1300 万件で 2.6 GB 台
      expect(e.storageLabel, '約2.6 GB');
    });

    test('件数が分からなければ出さない', () {
      expect(const ScanEstimate(items: 0).storageBytes, 0);
      expect(const ScanEstimate(items: 0).storageLabel, '—');
      expect(const ScanEstimate(items: 0).lightStorageLabel, '—');
    });

    test('関係だけ残すなら、該当する割合ぶんだけ', () {
      const e = ScanEstimate(items: 13000000);
      expect(e.lightStorageBytes,
          (13000000 * 0.02 * (136 + 266)).round());
      // 1300 万件でも 100 MB 程度
      expect(e.lightStorageLabel, '約100 MB');
      expect(e.lightStorageBytes, lessThan(e.storageBytes ~/ 10));
    });

    String label(int bytes) => ScanEstimate.roughBytesLabel(bytes);

    test('1 MB 未満はそう書く', () {
      expect(label(300 * 1024), '1 MB未満');
    });

    test('100 MB までは 1 MB 単位', () {
      expect(label(42 * mb + 600 * 1024), '約43 MB');
    });

    test('100 MB を超えたら 10 MB 単位', () {
      expect(label(347 * mb), '約350 MB');
    });

    test('GB は 10 未満なら小数 1 桁', () {
      expect(label((2.84 * 1024 * mb).round()), '約2.8 GB');
      expect(label(12 * 1024 * mb + 700 * mb), '約13 GB');
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
