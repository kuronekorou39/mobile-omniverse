import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_item.dart';

/// アプリ全体で共有する通知キャッシュ（メモリ内）
class NotificationCacheService {
  NotificationCacheService._();
  static final instance = NotificationCacheService._();

  final Map<String, _AccountNotifications> _cache = {};

  /// 画面に表示済みの通知IDセット（永続化）
  final Map<String, Set<String>> _renderedIds = {};
  bool _loaded = false;

  /// キャッシュ取得
  List<NotificationItem> get(String accountId) =>
      _cache[accountId]?.notifications ?? [];

  String? getCursor(String accountId) => _cache[accountId]?.cursor;

  bool hasData(String accountId) =>
      _cache[accountId] != null && _cache[accountId]!.notifications.isNotEmpty;

  /// 全キャッシュをクリア（アカウント情報は残す）
  void clearAll() {
    _cache.clear();
  }

  /// 新規フェッチ結果をマージ（重複排除、新しいものを先頭に）
  int merge(String accountId, List<NotificationItem> fetched, {String? cursor}) {
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
        newItems.add(n);
      } else if (n.totalActorCount > old.totalActorCount) {
        final idx = existing.notifications.indexOf(old);
        if (idx >= 0) existing.notifications[idx] = n;
        // アクター増加 → 再表示対象にする（renderedIdsから削除）
        _renderedIds[accountId]?.remove(n.id);
        newItems.add(n);
      }
    }
    if (newItems.isNotEmpty) {
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

  /// 永続化された表示済みIDを読み込む
  Future<void> loadRenderedIds() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('notif_rendered_'));
    for (final key in keys) {
      final accountId = key.replaceFirst('notif_rendered_', '');
      final ids = prefs.getStringList(key);
      if (ids != null) {
        _renderedIds[accountId] = ids.toSet();
      }
    }
  }

  /// 通知が画面に描画されたことを記録
  void markRendered(String accountId, String notificationId) {
    _renderedIds.putIfAbsent(accountId, () => {});
    _renderedIds[accountId]!.add(notificationId);
  }

  /// 通知画面を離れる時に呼ぶ — 表示済みIDを永続化 + バッジクリア
  Future<void> markSeen(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = _renderedIds[accountId];
    if (ids != null) {
      // 上限を超えたら古いIDを捨てる（メモリ節約）
      if (ids.length > 500) {
        final notifications = get(accountId);
        final currentIds = notifications.map((n) => n.id).toSet();
        ids.retainAll(currentIds);
      }
      await prefs.setStringList('notif_rendered_$accountId', ids.toList());
    }
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

  /// この通知が「新着」（まだ画面に表示されていない）かどうか
  bool isNew(String accountId, String notificationId) {
    final rendered = _renderedIds[accountId];
    if (rendered == null) return false; // 一度もタブを開いていない
    return !rendered.contains(notificationId);
  }
}

class _AccountNotifications {
  _AccountNotifications(this.notifications, this.cursor);
  final List<NotificationItem> notifications;
  String? cursor;
}
