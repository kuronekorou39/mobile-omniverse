/// アカウント作成日の文字列を日時にする。
///
/// X は "Thu Apr 06 15:24:15 +0000 2023"、Bluesky は ISO 8601 で返す。
/// どちらも users.createdAt にそのまま入っているので、読むときにここでそろえる。
/// 読めなければ null（取得できなかった相手は空文字で入っている）
DateTime? parseAccountCreatedAt(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;

  // "Thu Apr 06 15:24:15 +0000 2023"
  final parts = s.split(RegExp(r'\s+'));
  if (parts.length < 6) return null;
  final month = _months[parts[1]];
  final day = int.tryParse(parts[2]);
  final year = int.tryParse(parts[5]);
  if (month == null || day == null || year == null) return null;
  final time = parts[3].split(':');
  if (time.length != 3) return null;
  final h = int.tryParse(time[0]);
  final m = int.tryParse(time[1]);
  final sec = int.tryParse(time[2]);
  if (h == null || m == null || sec == null) return null;
  return DateTime.utc(year, month, day, h, m, sec);
}

const _months = {
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12,
};
