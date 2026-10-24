/// 3 桁ごとにカンマを入れる（12345 → 12,345）。
///
/// 件数・人数は桁が読み取れないと規模を取り違えるので、画面に出す数字は
/// 基本これを通す。省略形（1.2万）は幅が足りない場所だけに限る
String formatNumber(int value) {
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return value < 0 ? '-$buf' : buf.toString();
}
