import 'package:flutter/foundation.dart';

import '../utils/number_format.dart';
import 'block_scan_service.dart';
import 'follow_capture_engine.dart';
import 'follow_capture_job_service.dart';
import 'user_detail_service.dart';

/// 裏で長く走る取得の種類
enum FetchJobKind { followCapture, blockScan, userDetail }

/// いま走っている取得。画面の出し分けと、通知の文言に使う
@immutable
class RunningFetch {
  const RunningFetch({
    required this.kind,
    required this.title,
    required this.detail,
    this.done,
    this.total,
  });

  final FetchJobKind kind;

  /// 何をしているか。「つながり調査 @alice」など
  final String title;

  /// どこまで進んだか。「120 / 3,400 人」など
  final String detail;

  /// 割合が出せるときだけ入る。通知の進み具合に使う
  final int? done;
  final int? total;

  @override
  bool operator ==(Object other) =>
      other is RunningFetch &&
      other.kind == kind &&
      other.title == title &&
      other.detail == detail &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(kind, title, detail, done, total);
}

/// フォロー/フォロワー取得・つながり調査・詳しい情報の取得は、どれも
/// X への通信を一定の間隔で長時間続ける。並べて走らせると制限の枠を
/// 取り合ううえ、走査用 WebView は 1 枚しか無いので、1 本ずつしか走らせない。
///
/// それぞれのサービスは自分の進み具合しか知らないので、ここで束ねて
/// 「何かが走っているか」を 1 つの値で見せる。開始ボタンはこれを見て
/// 押せなくし、押せない理由を出す。
class FetchJobs {
  FetchJobs._() {
    for (final l in _sources) {
      l.addListener(_recompute);
    }
    _recompute();
  }

  static final instance = FetchJobs._();

  List<Listenable> get _sources => [
        FollowCaptureJobService.instance.progress,
        BlockScanService.instance.progress,
        UserDetailService.instance.progress,
      ];

  /// 走っている取得。何も走っていなければ null
  final current = ValueNotifier<RunningFetch?>(null);

  bool get isBusy => current.value != null;

  /// [self] 以外が走っていたら、始められない理由を投げる。
  /// 画面で押せなくしていても、起動時の自動再開などは画面を通らない
  void ensureIdle(FetchJobKind self) {
    final c = current.value;
    if (c == null || c.kind == self) return;
    throw StateError('「${c.title}」の実行中です');
  }

  void _recompute() {
    current.value = describe(
      capture: FollowCaptureJobService.instance.progress.value,
      scan: BlockScanService.instance.progress.value,
      detail: UserDetailService.instance.progress.value,
    );
  }

  /// 3 つの進み具合から、表に出す 1 本を決める。
  /// 1 本ずつしか走らせないが、念のため長くかかる順に優先する
  @visibleForTesting
  static RunningFetch? describe({
    FollowJobProgress? capture,
    BlockScanProgress? scan,
    UserDetailProgress? detail,
  }) {
    if (scan != null) {
      return RunningFetch(
        kind: FetchJobKind.blockScan,
        title: 'つながり調査 @${scan.targetHandle}',
        detail: scan.cancelling
            ? '中断しています'
            : '${formatNumber(scan.done)} / ${formatNumber(scan.total)} 人',
        done: scan.done,
        total: scan.total,
      );
    }
    if (detail != null) {
      return RunningFetch(
        kind: FetchJobKind.userDetail,
        title: '詳しい情報 @${detail.targetHandle}',
        detail: detail.cancelling
            ? '中断しています'
            : '${formatNumber(detail.done)} / ${formatNumber(detail.total)} 人',
        done: detail.done,
        total: detail.total,
      );
    }
    if (capture != null) {
      final kind =
          capture.kind == FollowListKind.followers ? 'フォロワー' : 'フォロー';
      return RunningFetch(
        kind: FetchJobKind.followCapture,
        title: '@${capture.targetHandle} の$kind',
        detail: capture.cancelling
            ? '中断しています'
            : '${formatNumber(capture.collected)} 件',
      );
    }
    return null;
  }
}
