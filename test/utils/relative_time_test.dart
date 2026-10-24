import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/utils/relative_time.dart';

void main() {
  final now = DateTime(2026, 10, 24, 12);

  test('24 時間以内は今日', () {
    expect(agoLabel(now.subtract(const Duration(hours: 5)), now: now), '今日');
    expect(agoLabel(now.add(const Duration(hours: 1)), now: now), '今日');
  });

  test('30 日未満は日', () {
    expect(agoLabel(now.subtract(const Duration(days: 3)), now: now), '3日前');
  });

  test('1 年未満は月', () {
    expect(agoLabel(now.subtract(const Duration(days: 95)), now: now), '3か月前');
  });

  test('1 年以上は年と月', () {
    expect(agoLabel(now.subtract(const Duration(days: 370)), now: now), '1年前');
    expect(
        agoLabel(now.subtract(const Duration(days: 365 + 100)), now: now),
        '1年3か月前');
  });
}
