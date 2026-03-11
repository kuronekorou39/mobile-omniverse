import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_api_service.dart';

final notificationBadgeProvider =
    StateNotifierProvider<NotificationBadgeNotifier, bool>(
  (ref) => NotificationBadgeNotifier(),
);

/// 通知バッジ（未読ドット）の管理
class NotificationBadgeNotifier extends StateNotifier<bool> {
  NotificationBadgeNotifier() : super(false);

  int _fetchCycleCount = 0;
  static const _checkEveryNCycles = 3; // 3回に1回チェック
  static const _prefsPrefix = 'notif_last_seen_';

  /// スケジューラのフェッチサイクルごとに呼ばれる
  /// N回に1回だけ実際の通知チェックを行う
  Future<void> onSchedulerCycle() async {
    _fetchCycleCount++;
    if (_fetchCycleCount % _checkEveryNCycles != 0) return;
    await checkForNew();
  }

  /// 全有効アカウントの最新通知をチェック
  Future<void> checkForNew() async {
    final accounts = AccountStorageService.instance.accounts
        .where((a) => a.isEnabled)
        .toList();
    if (accounts.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    for (final account in accounts) {
      try {
        String? latestId;

        if (account.service == SnsService.x) {
          final result = await XApiService.instance
              .getNotifications(account.xCredentials, count: 1);
          if (result.notifications.isNotEmpty) {
            latestId = result.notifications.first.id;
          }
        } else {
          final result = await BlueskyApiService.instance
              .getNotifications(account.blueskyCredentials, limit: 1);
          if (result.notifications.isNotEmpty) {
            latestId = result.notifications.first.id;
          }
        }

        if (latestId != null) {
          final lastSeen = prefs.getString('$_prefsPrefix${account.id}');
          if (lastSeen != latestId) {
            state = true;
            return; // 1つでも未読があればバッジ表示
          }
        }
      } catch (e) {
        debugPrint('[NotifBadge] Error checking ${account.handle}: $e');
      }
    }
  }

  /// 通知画面を開いたとき、現在の最新通知IDを保存してバッジを消す
  Future<void> markSeen() async {
    state = false;

    final accounts = AccountStorageService.instance.accounts
        .where((a) => a.isEnabled)
        .toList();
    if (accounts.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    for (final account in accounts) {
      try {
        String? latestId;

        if (account.service == SnsService.x) {
          final result = await XApiService.instance
              .getNotifications(account.xCredentials, count: 1);
          if (result.notifications.isNotEmpty) {
            latestId = result.notifications.first.id;
          }
        } else {
          final result = await BlueskyApiService.instance
              .getNotifications(account.blueskyCredentials, limit: 1);
          if (result.notifications.isNotEmpty) {
            latestId = result.notifications.first.id;
          }
        }

        if (latestId != null) {
          await prefs.setString('$_prefsPrefix${account.id}', latestId);
        }
      } catch (e) {
        debugPrint('[NotifBadge] Error marking seen for ${account.handle}: $e');
      }
    }
  }
}
