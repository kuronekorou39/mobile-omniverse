import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/utils/number_format.dart';

void main() {
  test('3 桁ごとにカンマを入れる', () {
    expect(formatNumber(0), '0');
    expect(formatNumber(999), '999');
    expect(formatNumber(1000), '1,000');
    expect(formatNumber(12345), '12,345');
    expect(formatNumber(12000000), '12,000,000');
    expect(formatNumber(-1234), '-1,234');
  });
}
