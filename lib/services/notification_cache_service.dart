import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_item.dart';

/// アプリ全体で共有する通知キャッシュ（メモリ内）
class NotificationCacheService {
  NotificationCacheService._();
  static final instance = NotificationCacheService._();

  final Map<String, _AccountNotifications> _cache = {};

  /// アカウントごとの既読ライン（この時刻より新しい通知がハイライト対象）
  final Map<String, DateTime> _readLines = {};
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
    // type+targetPostIdで同一イベントの重複を検出（IDが異なるケース対応）
    final existingEventKeys = <String>{
      for (final n in existing.notifications)
        if (n.targetPostId != null) '${n.type.name}:${n.targetPostId}',
    };
    final newItems = <NotificationItem>[];
    int updatedCount = 0;
    for (final n in stamped) {
      final old = existingMap[n.id];
      if (old != null) {
        // ID完全一致: アクター数が増えていれば更新
        if (n.totalActorCount > old.totalActorCount) {
          final idx = existing.notifications.indexOf(old);
          if (idx >= 0) existing.notifications[idx] = n;
          updatedCount++;
        }
      } else {
        // IDは異なるが同一イベント（同じtype+targetPostId）なら
        // 既存をアクター数が多い方に更新して重複追加しない
        final eventKey = n.targetPostId != null ? '${n.type.name}:${n.targetPostId}' : null;
        if (eventKey != null && existingEventKeys.contains(eventKey)) {
          final oldEvent = existing.notifications.firstWhere(
            (e) => e.targetPostId == n.targetPostId && e.type == n.type,
          );
          if (n.totalActorCount >= oldEvent.totalActorCount) {
            final idx = existing.notifications.indexOf(oldEvent);
            if (idx >= 0) existing.notifications[idx] = n;
          }
          updatedCount++;
        } else {
          newItems.add(n);
          if (eventKey != null) existingEventKeys.add(eventKey);
        }
      }
    }
    if (newItems.isNotEmpty) {
      existing.notifications.insertAll(0, newItems);
    }
    if (cursor != null) existing.cursor = cursor;
    return newItems.length + updatedCount;
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
  Future<void> loadReadLines() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('notif_read_line_'));
    for (final key in keys) {
      final accountId = key.replaceFirst('notif_read_line_', '');
      final ms = prefs.getInt(key);
      if (ms != null) {
        _readLines[accountId] = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
  }

  /// タブを開いたときに呼ぶ: 既読ラインを読み取り、新しい既読ラインを保存
  /// 戻り値は「旧既読ライン」（ハイライト判定に使う）
  DateTime openTab(String accountId) {
    final oldLine = _readLines[accountId];
    _readLines[accountId] = DateTime.now();
    _saveReadLine(accountId);
    // 初回（既読ラインなし）は全て既読扱い
    return oldLine ?? DateTime.now();
  }

  /// 「すべて」タブを開いたときに呼ぶ: 全アカウントの既読ラインを更新
  /// 戻り値は「最も古い旧既読ライン」
  DateTime openAllTab(List<String> accountIds) {
    final now = DateTime.now();
    DateTime oldest = now;
    for (final id in accountIds) {
      final oldLine = _readLines[id] ?? now; // 初回は全て既読扱い
      if (oldLine.isBefore(oldest)) oldest = oldLine;
      _readLines[id] = now;
      _saveReadLine(id);
    }
    return oldest;
  }

  Future<void> _saveReadLine(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final line = _readLines[accountId];
    if (line != null) {
      await prefs.setInt('notif_read_line_$accountId', line.millisecondsSinceEpoch);
    }
  }

  /// 通知が既読ラインより新しいかどうか
  bool isNew(String accountId, DateTime readLine, DateTime notificationTimestamp) {
    return notificationTimestamp.isAfter(readLine);
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

}

class _AccountNotifications {
  _AccountNotifications(this.notifications, this.cursor);
  final List<NotificationItem> notifications;
  String? cursor;
}
