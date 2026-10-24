import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/utils/account_date.dart';

void main() {
  test('X の形式を読む', () {
    expect(parseAccountCreatedAt('Thu Apr 06 15:24:15 +0000 2023'),
        DateTime.utc(2023, 4, 6, 15, 24, 15));
  });

  test('Bluesky の ISO 8601 を読む', () {
    expect(parseAccountCreatedAt('2024-02-29T10:00:00.000Z'),
        DateTime.utc(2024, 2, 29, 10));
  });

  test('空や壊れた値は null', () {
    expect(parseAccountCreatedAt(''), isNull);
    expect(parseAccountCreatedAt('Thu Apr'), isNull);
    expect(parseAccountCreatedAt('Thu Xyz 06 15:24:15 +0000 2023'), isNull);
  });
}
