import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/screens/birthday_screen.dart';

void main() {
  test('今月から 12 か月ぶん回る', () {
    expect(monthsStartingFrom(10), [10, 11, 12, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(monthsStartingFrom(1).first, 1);
    expect(monthsStartingFrom(12).last, 11);
  });

  test('満年齢は今年の誕生日が来ていなければ 1 引く', () {
    final now = DateTime(2026, 10, 24);
    expect(ageOf(year: 1990, month: 4, day: 6, now: now), 36);
    expect(ageOf(year: 1990, month: 12, day: 1, now: now), 35);
    expect(ageOf(year: 1990, month: 10, day: 24, now: now), 36);
    expect(ageOf(year: null, month: 1, day: 1, now: now), isNull);
  });
}
