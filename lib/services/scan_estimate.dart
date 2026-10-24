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

  // ─── 保存容量 ───
  //
  // つながり調査は 1 件につき block_findings 1 行と、初めて見た相手なら
  // users 1 行を書く。SQLite ファイルを実測した値（索引込み、VACUUM 後）

  /// 延べ 1 件ぶんの行と索引
  static const int bytesPerFinding = 136;

  /// 調査で初めて出てきた相手 1 人ぶんの users 行（自己紹介と場所は捨てている）
  static const int bytesPerScanUser = 266;

  /// 延べ件数のうち、初めて見る相手の割合。
  ///
  /// 同じ界隈の人は同じ相手をフォローしているので、起点の人数が増えるほど
  /// 重複が増えて下がる。始める前には分からないので、ほどほどの値を置く
  static const double uniqueShare = 0.3;

  /// 延べ 1 件あたりのおよその容量
  static const double bytesPerItem =
      bytesPerFinding + bytesPerScanUser * uniqueShare;

  /// 調査を終えたときに増えるファイルのおよその大きさ（フォロー先を全部残す）
  int get storageBytes => items <= 0 ? 0 : (items * bytesPerItem).round();

  /// 「約2.8 GB」「約300 MB」。桁が分かればよい
  String get storageLabel => roughBytesLabel(storageBytes);

  /// 延べ件数のうち、ブロックかミュートが立っている割合。
  ///
  /// 他人のフォロー先に自分と関係のある人が混ざる率は低い。前もって
  /// 分からないので、上振れ側に置く
  static const double relationShare = 0.02;

  /// 関係のある人だけ残す調査で増えるおよその大きさ。
  /// 該当者はほぼ毎回初めて見る相手なので、users のぶんも全員分で見る
  int get lightStorageBytes => items <= 0
      ? 0
      : (items * relationShare * (bytesPerFinding + bytesPerScanUser)).round();

  String get lightStorageLabel => roughBytesLabel(lightStorageBytes);

  @visibleForTesting
  static String roughBytesLabel(int bytes) {
    const mb = 1024 * 1024;
    const gb = 1024 * mb;
    if (bytes <= 0) return '—';
    if (bytes < mb) return '1 MB未満';
    if (bytes < gb) {
      final m = bytes / mb;
      // 100 MB を超えたら 1 MB の差は意味がない
      final shown = m < 100 ? m.round() : (m / 10).round() * 10;
      return '約$shown MB';
    }
    final g = bytes / gb;
    return g < 10 ? '約${g.toStringAsFixed(1)} GB' : '約${g.round()} GB';
  }

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
