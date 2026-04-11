import '../models/notification_item.dart';

/// アプリ全体で共有する通知キャッシュ（メモリ内）
class NotificationCacheService {
  NotificationCacheService._();
  static final instance = NotificationCacheService._();

  final Map<String, _AccountNotifications> _cache = {};

  /// 通知画面を開いた時点で見たIDセット（ハイライト判定用）
  final Map<String, Set<String>> _seenIds = {};

  /// キャッシュ取得
  List<NotificationItem> get(String accountId) =>
      _cache[accountId]?.notifications ?? [];

  String? getCursor(String accountId) => _cache[accountId]?.cursor;

  bool hasData(String accountId) =>
      _cache[accountId] != null && _cache[accountId]!.notifications.isNotEmpty;

  /// 新規フェッチ結果をマージ（重複排除、新しいものを先頭に）
  /// 各通知に accountId を注入する
  int merge(String accountId, List<NotificationItem> fetched, {String? cursor}) {
    // accountId を注入
    final stamped = fetched.map((n) =>
        n.accountId == accountId ? n : n.copyWith(accountId: accountId)).toList();

    final existing = _cache[accountId];
    if (existing == null || existing.notifications.isEmpty) {
      _cache[accountId] = _AccountNotifications(List.of(stamped), cursor);
      return stamped.length;
    }

    final existingMap = {for (final n in existing.notifications) n.id: n};
    final newItems = <NotificationItem>[];
    for (final n in stamped) {
      final old = existingMap[n.id];
      if (old == null) {
        // 新規
        newItems.add(n);
      } else if (n.totalActorCount > old.totalActorCount) {
        // 同じIDだがアクター数が増えた → 更新＋新着扱い
        final idx = existing.notifications.indexOf(old);
        if (idx >= 0) existing.notifications[idx] = n;
        newItems.add(n); // 新着として扱う（ハイライト用）
      }
    }
    if (newItems.isNotEmpty) {
      // 更新された既存アイテム以外の新規を先頭に挿入
      final newOnly = newItems.where((n) => !existingMap.containsKey(n.id)).toList();
      if (newOnly.isNotEmpty) {
        existing.notifications.insertAll(0, newOnly);
      }
    }
    if (cursor != null) existing.cursor = cursor;
    return newItems.length;
  }

  /// loadMore結果を末尾に追加
  void append(String accountId, List<NotificationItem> items, String? cursor) {
    final existing = _cache[accountId];
    if (existing == null) {
      _cache[accountId] = _AccountNotifications(List.of(items), cursor);
      return;
    }
    final existingIds = existing.notifications.map((n) => n.id).toSet();
    final newItems = items.where((n) => !existingIds.contains(n.id)).toList();
    existing.notifications.addAll(newItems);
    if (cursor != null) existing.cursor = cursor;
  }

  /// 通知画面を開いた時に呼ぶ — 現在のIDを「既読」として記録
  void markSeen(String accountId) {
    final notifications = get(accountId);
    _seenIds[accountId] = notifications.map((n) => n.id).toSet();
  }

  /// 全アカウントの通知を時系列でマージして返す
  List<NotificationItem> getAllMerged(List<String> accountIds) {
    final all = <NotificationItem>[];
    for (final id in accountIds) {
      all.addAll(get(id));
    }
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all;
  }

  /// この通知が「新着」（前回画面を開いた後に追加された）かどうか
  bool isNew(String accountId, String notificationId) {
    final seen = _seenIds[accountId];
    if (seen == null) return false; // 一度も開いていない場合はハイライトしない
    return !seen.contains(notificationId);
  }
}

class _AccountNotifications {
  _AccountNotifications(this.notifications, this.cursor);
  final List<NotificationItem> notifications;
  String? cursor;
}
