import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_log.dart';
import '../models/sns_service.dart';

class ActivityLogNotifier extends StateNotifier<List<ActivityLog>> {
  ActivityLogNotifier() : super([]);

  static const _maxEntries = 300;

  void add(ActivityLog log) {
    state = [log, ...state];
    if (state.length > _maxEntries) {
      state = state.sublist(0, _maxEntries);
    }
  }

  void logAction({
    required ActivityAction action,
    required SnsService platform,
    required String accountHandle,
    String? accountId,
    String? targetId,
    String? targetSummary,
    required bool success,
    int? statusCode,
    String? errorMessage,
    String? responseSnippet,
  }) {
    add(ActivityLog(
      timestamp: DateTime.now(),
      action: action,
      platform: platform,
      accountHandle: accountHandle,
      accountId: accountId,
      targetId: targetId,
      targetSummary: targetSummary,
      success: success,
      statusCode: statusCode,
      errorMessage: errorMessage,
      responseSnippet: responseSnippet,
    ));
  }

  /// TL 取得ログのみ (アカウント別の最終取得時刻確認用)
  List<ActivityLog> get timelineFetchLogs =>
      state.where((l) => l.action == ActivityAction.timelineFetch).toList();

  /// コミット操作ログのみ (いいね、リポスト等)
  List<ActivityLog> get commitLogs =>
      state.where((l) => l.action != ActivityAction.timelineFetch).toList();

  void clear() {
    state = [];
  }
}

final activityLogProvider =
    StateNotifierProvider<ActivityLogNotifier, List<ActivityLog>>(
  (ref) => ActivityLogNotifier(),
);
