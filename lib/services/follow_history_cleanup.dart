import 'package:flutter/foundation.dart';

import '../models/sns_service.dart';
import 'follow_db.dart';

/// 古い取得履歴の削除を裏で進める。
///
/// 件数が多いと数十秒かかる。画面を止めて待たせると何もできなくなるので、
/// 裏で走らせ、そのあいだはその対象の履歴に触る操作（履歴を開く・
/// 今すぐ取得・対象の削除・もう一度の削除）だけを止める。
class FollowHistoryCleanup {
  FollowHistoryCleanup._();
  static final instance = FollowHistoryCleanup._();

  /// 削除中の対象
  final busy = ValueNotifier<Set<FollowTargetKey>>(const {});

  bool isBusy(SnsService service, String handle) =>
      busy.value.contains((service: service, handle: handle));

  /// 削除を始める。終わったら消した件数を返す。
  /// 同じ対象で削除中なら何もせず null を返す
  Future<int?> run(
    SnsService service,
    String handle, {
    required int keepPerKind,
    int? runningSnapshotId,
  }) async {
    final key = (service: service, handle: handle);
    if (busy.value.contains(key)) return null;
    busy.value = {...busy.value, key};
    try {
      return await FollowDb.instance.deleteOldSnapshots(service, handle,
          keepPerKind: keepPerKind, runningSnapshotId: runningSnapshotId);
    } finally {
      busy.value = {...busy.value}..remove(key);
    }
  }
}
