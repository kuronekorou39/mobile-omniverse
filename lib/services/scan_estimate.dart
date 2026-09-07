import 'package:flutter/foundation.dart';

/// つながり調査の所要時間の目安。
///
/// 走査は 1 ページごとに間隔を空けて投げるので、速さは送信間隔と 1 ページの
/// 件数で決まる。実績から測る手もあるが、取得は中断・再開ができるため
/// 記録に残る時間には放置ぶんが混ざり、あてにならない。素直に理論値で出す。
///
/// 実際はレート制限の待機や、非公開で取れない相手のぶん遅くなるので、
/// これは**下限**（最短でこれくらい）として読む。
class ScanEstimate {
  const ScanEstimate({required this.items});

  /// たどる延べ件数（起点の人たちのフォロー数の合計）
  final int items;

  /// 1 ページで返る件数。X のフォロー一覧の実測
  static const int itemsPerPage = 50;

  /// 1 ページごとの送信間隔（秒）。BlockScanService の走査間隔と同じ
  static const int pageIntervalSeconds = 2;

  /// 2 秒ごとに 50 件 = 毎分 1500 件
  static const double ratePerMinute =
      itemsPerPage * 60 / pageIntervalSeconds;

  Duration get duration {
    if (items <= 0) return Duration.zero;
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
