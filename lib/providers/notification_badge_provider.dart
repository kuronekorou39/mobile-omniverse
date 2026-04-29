import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sns_service.dart';
import '../services/account_storage_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/notification_cache_service.dart';
import '../services/x_api_service.dart';

final notificationBadgeProvider =
    StateNotifierProvider<NotificationBadgeNotifier, NotificationBadgeState>(
  (ref) => NotificationBadgeNotifier(),
);

/// 通知タブが現在アクティブ（bottom nav で選択中）か
///
/// IndexedStack は非アクティブタブも layout するため、バックグラウンドで
/// ListView.builder がタイルを mount → initState で markSeen が走ってしまう。
/// このフラグでタブ非アクティブ時の markSeen を抑制する。
final notificationTabActiveProvider = StateProvider<bool>((ref) => false);

/// 通知バッジの状態。アカウント別の未読件数も保持し、
/// アカウントタブの数字バッジ + 全体合計（ホーム下部）に使う。
class NotificationBadgeState {
  const NotificationBadgeState({
    this.unreadAccountIds = const {},
    this.unreadCounts = const {},
  });

  final Set<String> unreadAccountIds;
  final Map<String, int> unreadCounts;

  bool get isEmpty => unreadAccountIds.isEmpty;
  bool get isNotEmpty => unreadAccountIds.isNotEmpty;
  bool contains(String accountId) => unreadAccountIds.contains(accountId);
  int countFor(String accountId) => unreadCounts[accountId] ?? 0;
  int get total =>
      unreadCounts.values.fold(0, (sum, count) => sum + count);
}

/// 通知バッジの管理 + バックグラウンド通知フェッチ。
class NotificationBadgeNotifier extends StateNotifier<NotificationBadgeState> {
  NotificationBadgeNotifier() : super(const NotificationBadgeState());

  int _fetchCycleCount = 0;
  static const _checkEveryNCycles = 5; // 5回に1回チェック
  final _cache = NotificationCacheService.instance;

  /// 全体で未読があるかどうか（home_screen のバッジ用）
  bool get hasUnread => state.isNotEmpty;

  /// 特定アカウントに未読があるか
  bool hasUnreadFor(String accountId) => state.contains(accountId);

  /// 特定アカウントの未読件数
  int unreadCountFor(String accountId) => state.countFor(accountId);

  /// 全アカウントの未読合計
  int get totalUnread => state.total;

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

    _recompute(accounts.map((a) => a.id).toList());
  }

  void _recompute(List<String> accountIds) {
    final newUnread = _cache.unseenAccountIds(accountIds);
    final newCounts = _cache.unseenCounts(accountIds);
    if (!_setEquals(newUnread, state.unreadAccountIds) ||
        !_mapEquals(newCounts, state.unreadCounts)) {
      state = NotificationBadgeState(
        unreadAccountIds: newUnread,
        unreadCounts: newCounts,
      );
    }
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  bool _mapEquals(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// 通知タブに入った時や個別通知が既読化された時に呼ぶ。
  /// バッジドット + 件数バッジを即座に再計算する。
  void refreshBadge(List<String> accountIds) {
    _recompute(accountIds);
  }

  /// 通知画面を開いたとき、バッジを消して既読マーク
  Future<void> markSeen() async {
    state = const NotificationBadgeState();
  }
}
