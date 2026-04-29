import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fetch_status_provider.dart' show AccountFetchStatus, AccountHealth;

/// 通知取得の健全性。タイムライン取得とは独立に管理し、通知タブの
/// アカウントチップに状態ドットを表示する。

class NotificationFetchStatusNotifier
    extends StateNotifier<Map<String, AccountFetchStatus>> {
  NotificationFetchStatusNotifier() : super({});

  /// フェッチ結果を反映
  /// - 成功 → green (失敗カウンタリセット)
  /// - 1回失敗 → yellow
  /// - 2回以上連続失敗 → red
  void update(String accountId, bool success) {
    final current = state[accountId] ?? const AccountFetchStatus();

    if (success) {
      state = {
        ...state,
        accountId: const AccountFetchStatus(
          health: AccountHealth.good,
          consecutiveFailures: 0,
        ),
      };
    } else {
      final failures = current.consecutiveFailures + 1;
      state = {
        ...state,
        accountId: AccountFetchStatus(
          health:
              failures >= 2 ? AccountHealth.error : AccountHealth.warning,
          consecutiveFailures: failures,
        ),
      };
    }
  }
}

final notificationFetchStatusProvider = StateNotifierProvider<
    NotificationFetchStatusNotifier, Map<String, AccountFetchStatus>>(
  (ref) => NotificationFetchStatusNotifier(),
);
