import 'package:flutter_riverpod/flutter_riverpod.dart';

/// アカウントごとのフェッチ健全性
enum AccountHealth { unknown, good, warning, error }

class AccountFetchStatus {
  const AccountFetchStatus({
    this.health = AccountHealth.unknown,
    this.consecutiveFailures = 0,
  });

  final AccountHealth health;
  final int consecutiveFailures;
}

class FetchStatusNotifier extends StateNotifier<Map<String, AccountFetchStatus>> {
  FetchStatusNotifier() : super({});

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
          health: failures >= 2 ? AccountHealth.error : AccountHealth.warning,
          consecutiveFailures: failures,
        ),
      };
    }
  }

  /// トークン期限切れ → 即座に red
  void setExpired(String accountId) {
    state = {
      ...state,
      accountId: const AccountFetchStatus(
        health: AccountHealth.error,
        consecutiveFailures: 99,
      ),
    };
  }
}

final fetchStatusProvider =
    StateNotifierProvider<FetchStatusNotifier, Map<String, AccountFetchStatus>>(
  (ref) => FetchStatusNotifier(),
);
