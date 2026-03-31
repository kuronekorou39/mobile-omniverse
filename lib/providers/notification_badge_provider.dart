import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_item.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/notification_cache_service.dart';
import '../services/x_api_service.dart';

final notificationBadgeProvider =
    StateNotifierProvider<NotificationBadgeNotifier, bool>(
  (ref) => NotificationBadgeNotifier(),
);

/// 通知バッジ（未読ドット）の管理 + バックグラウンド通知フェッチ
class NotificationBadgeNotifier extends StateNotifier<bool> {
  NotificationBadgeNotifier() : super(false);

  int _fetchCycleCount = 0;
  static const _checkEveryNCycles = 3; // 3回に1回チェック
  static const _prefsPrefix = 'notif_last_seen_';
  final _cache = NotificationCacheService.instance;

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

    final prefs = await SharedPreferences.getInstance();
    bool hasNew = false;

    for (final account in accounts) {
      try {
        List<NotificationItem> fetched;

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
          fetched = merged;
          _cache.merge(account.id, fetched, cursor: notifResult.cursor);
        } else {
          final result = await BlueskyApiService.instance
              .getNotificationsWithRefresh(account.blueskyCredentials);
          fetched = result.notifications;
          _cache.merge(account.id, fetched, cursor: result.cursor);
        }

        // バッジチェック
        if (fetched.isNotEmpty) {
          final lastSeen = prefs.getString('$_prefsPrefix${account.id}');
          if (lastSeen != fetched.first.id) {
            hasNew = true;
          }
        }
      } catch (e) {
        debugPrint('[NotifBadge] Error fetching ${account.handle}: $e');
      }
    }

    if (hasNew && !state) state = true;
  }

  /// 通知画面を開いたとき、バッジを消して既読マーク
  Future<void> markSeen() async {
    state = false;

    final accounts = AccountStorageService.instance.accounts
        .where((a) => a.isEnabled)
        .toList();
    if (accounts.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    for (final account in accounts) {
      // キャッシュ内の現在の通知を既読として記録
      _cache.markSeen(account.id);

      final notifications = _cache.get(account.id);
      if (notifications.isNotEmpty) {
        await prefs.setString(
            '$_prefsPrefix${account.id}', notifications.first.id);
      }
    }
  }
}
