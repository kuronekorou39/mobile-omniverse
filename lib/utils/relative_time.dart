/// 「3日前」「2か月前」。一覧で古さを比べるためのものなので、桁が分かる粗さにする
String agoLabel(DateTime at, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.isNegative || d.inHours < 24) return '今日';
  final days = d.inDays;
  if (days < 30) return '$days日前';
  if (days < 365) return '${days ~/ 30}か月前';
  final years = days ~/ 365;
  final months = (days % 365) ~/ 30;
  return months == 0 ? '$years年前' : '$years年$monthsか月前';
}
