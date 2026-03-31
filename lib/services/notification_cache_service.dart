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
  int merge(String accountId, List<NotificationItem> fetched, {String? cursor}) {
    final existing = _cache[accountId];
    if (existing == null || existing.notifications.isEmpty) {
      _cache[accountId] = _AccountNotifications(List.of(fetched), cursor);
      return fetched.length;
    }

    final existingIds = existing.notifications.map((n) => n.id).toSet();
    final newItems = fetched.where((n) => !existingIds.contains(n.id)).toList();
    if (newItems.isNotEmpty) {
      existing.notifications.insertAll(0, newItems);
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
