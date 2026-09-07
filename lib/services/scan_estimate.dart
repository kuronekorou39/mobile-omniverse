import 'package:flutter/foundation.dart';

/// つながり調査の所要時間の見積もり。
///
/// 1 ページの件数は X が返したリクエストをそのまま再送しているので
/// コードからは分からず、待ち時間もレート制限で伸び縮みする。だから
/// 理論値ではなく、**この端末での過去の取得実績**（何件を何分で取れたか）
/// を使う。実績が無いうちは、実測から得られた控えめな既定値を置く。
class ScanEstimate {
  const ScanEstimate({required this.items, required this.ratePerMinute});

  /// たどる延べ件数（起点の人たちのフォロー数の合計）
  final int items;

  /// 1 分あたりに取れる件数
  final double ratePerMinute;

  /// 実績が無いときの既定値。1 ページ 2 秒の間隔と、実測で多い
  /// 1 ページ 50 件前後から置いた控えめな値
  static const double defaultRatePerMinute = 1500;

  Duration get duration {
    if (items <= 0 || ratePerMinute <= 0) return Duration.zero;
    return Duration(seconds: (items / ratePerMinute * 60).round());
  }

  /// 「約3時間」「約40分」。細かい端数は当てにならないので丸める
  String get label => roughLabel(duration);

  /// 見積もりは上振れも下振れもするので、桁が伝わればよい
  @visibleForTesting
  static String roughLabel(Duration d) {
    if (d <= Duration.zero) return '—';
    if (d.inMinutes < 1) return '1分未満';
    if (d.inMinutes < 60) return '約${d.inMinutes}分';
    if (d.inHours < 24) {
      final h = d.inHours;
      final m = d.inMinutes % 60;
      // 3 時間を超えたら分まで出しても意味がない
      if (h >= 3 || m < 10) return '約$h時間';
      return '約$h時間${(m ~/ 10) * 10}分';
    }
    final days = d.inDays;
    final h = d.inHours % 24;
    return h < 3 ? '約$days日' : '約$days日$h時間';
  }
}
