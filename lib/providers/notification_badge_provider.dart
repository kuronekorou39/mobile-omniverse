import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_item.dart';
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
  static const _checkEveryNCycles = 3; // 3回に1回チェック
  static const _prefsPrefix = 'notif_last_seen_';
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
  Future<void> _fetchAndCheck() async {
    final accounts = AccountStorageService.instance.accounts
        .where((a) => a.isEnabled)
        .toList();
    if (accounts.isEmpty) return;

    final newUnread = <String>{...state};

    for (final account in accounts) {
      try {
        int newCount;

        if (account.service == SnsService.x) {
          final results = await Future.wait([
            XApiService.instance.getNotifications(account.xCredentials),
            XApiService.instance.getMentionNotifications(account.xCredentials),
          ]);
          final notifResult = results[0] as ({List<NotificationItem> notifications, String? cursor, String? responseSnippet});
          final mentions = results[1] as List<NotificationItem>;
          final merged = [...notifResult.notifications, ...mentions];
          final seen = <String>{};
          merged.retainWhere((n) => seen.add(n.id));
          merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          newCount = _cache.merge(account.id, merged, cursor: notifResult.cursor);
        } else {
          final result = await BlueskyApiService.instance
              .getNotificationsWithRefresh(account.blueskyCredentials);
          newCount = _cache.merge(account.id, result.notifications, cursor: result.cursor);
        }

        // 実際にキャッシュに新規追加された件数でバッジ判定
        if (newCount > 0) {
          newUnread.add(account.id);
        }
      } catch (e) {
        debugPrint('[NotifBadge] Error fetching ${account.handle}: $e');
      }
    }

    if (newUnread != state) state = newUnread;
  }

  /// 通知画面を開いたとき、バッジを消して既読マーク
  Future<void> markSeen() async {
    state = {};

    final accounts = AccountStorageService.instance.accounts
        .where((a) => a.isEnabled)
        .toList();

    for (final account in accounts) {
      _cache.markSeen(account.id);
    }
  }
}
