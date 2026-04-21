import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/notification_cache_service.dart';
import '../services/x_api_service.dart';

final notificationBadgeProvider =
    StateNotifierProvider<NotificationBadgeNotifier, Set<String>>(
  (ref) => NotificationBadgeNotifier(),
);

/// 通知バッジ（未読ドット）の管理 + バックグラウンド通知フェッチ
/// state = 新着通知があるアカウントIDの集合
class NotificationBadgeNotifier extends StateNotifier<Set<String>> {
  NotificationBadgeNotifier() : super({});

  int _fetchCycleCount = 0;
  static const _checkEveryNCycles = 5; // 5回に1回チェック
  final _cache = NotificationCacheService.instance;

  /// 全体で未読があるかどうか（home_screen のバッジ用）
  bool get hasUnread => state.isNotEmpty;

  /// 特定アカウントに未読があるか
  bool hasUnreadFor(String accountId) => state.contains(accountId);

  /// スケジューラのフェッチサイクルごとに呼ばれる
  /// N回に1回だけ実際の通知チェック+フェッチを行う
  Future<void> onSchedulerCycle() async {
    _fetchCycleCount++;
    if (_fetchCycleCount % _checkEveryNCycles != 0) return;
    await _fetchAndCheck();
  }

  /// 全有効アカウントの通知をフェッチしてキャッシュ + バッジ更新
  ///
  /// バッジ点灯判定は cache.hasUnseenFor() で毎回再計算する:
  /// - 未見通知がある → 点灯
  /// - 全て既読化済み → 消灯
  /// これにより「通知タブで見た→自動消灯」が次スケジューラサイクルで反映される
  Future<void> _fetchAndCheck() async {
    final accounts = AccountStorageService.instance.accounts
        .where((a) => a.isEnabled)
        .toList();
    if (accounts.isEmpty) return;

    for (final account in accounts) {
      try {
        if (account.service == SnsService.x) {
          // バックグラウンドではall.jsonのみ（レート制限節約）
          final notifResult = await XApiService.instance
              .getNotifications(account.xCredentials);
          _cache.merge(account.id, notifResult.notifications,
              cursor: notifResult.cursor);
        } else {
          final result = await BlueskyApiService.instance
              .getNotificationsWithRefresh(account.blueskyCredentials);
          _cache.merge(account.id, result.notifications,
              cursor: result.cursor);
        }
      } catch (e) {
        debugPrint('[NotifBadge] Error fetching ${account.handle}: $e');
      }
    }

    final accountIds = accounts.map((a) => a.id).toList();
    final newUnread = _cache.unseenAccountIds(accountIds);
    if (!_setEquals(newUnread, state)) state = newUnread;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  /// 通知タブに入った時などに呼ぶ: バッジを即座に消す
  /// （個別通知の既読化は各タイルの cacheService.markSeen() が担当）
  void refreshBadge(List<String> accountIds) {
    final newUnread = _cache.unseenAccountIds(accountIds);
    if (!_setEquals(newUnread, state)) state = newUnread;
  }

  /// 通知画面を開いたとき、バッジを消して既読マーク
  Future<void> markSeen() async {
    state = {};
  }
}
