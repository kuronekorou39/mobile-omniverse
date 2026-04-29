import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_item.dart';

/// merge() の結果
class NotificationMergeResult {
  const NotificationMergeResult({
    required this.newCount,
    required this.updatedCount,
  });

  /// 新規追加された通知の件数
  final int newCount;

  /// 既存通知が更新された件数（アクター追加 or timestamp 進行）
  final int updatedCount;

  /// 何らかの変更があったか
  bool get hasChanges => newCount > 0 || updatedCount > 0;
}

/// アプリ全体で共有する通知キャッシュ（メモリ内）
///
/// ハイライト判定は eventKey ベースの `_seenAt` マップで一元管理する:
/// - `isNew(n)` = n.timestamp が前回閲覧時刻より新しい
/// - `markSeen(n)` = 閲覧時刻を now で更新（次からは既読扱い）
/// - 同一イベントが内容更新 (timestamp 進行) されれば自動的に未読復活 → 再ハイライト
class NotificationCacheService {
  NotificationCacheService._();
  static final instance = NotificationCacheService._();

  final Map<String, _AccountNotifications> _cache = {};

  /// eventKey ごとの「ユーザーが最後にハイライトを見た時刻」
  final Map<String, DateTime> _seenAt = {};
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

  /// 同一イベント判定キー
  /// - targetPostId があれば `type:postId` （同じ投稿への複数アクションを集約）
  /// - なければ `type:id` （フォロー等は通知ID単位で独立）
  static String _eventKey(NotificationItem n) => n.targetPostId != null
      ? '${n.type.name}:${n.targetPostId}'
      : '${n.type.name}:${n.id}';

  /// 新規フェッチ結果をマージ
  ///
  /// 同一イベント (eventKey) の既存通知があれば:
  /// - 新データの timestamp が新しい or actor 数が増えていれば上書き
  /// - 最後に timestamp 降順で全体再ソート → 更新された通知が自動的に先頭へ移動
  ///
  /// 同一イベントの既存がなければ新規追加。
  /// 最後に eventKey の重複を保険的に除去（race condition や parse 異常対策）。
  NotificationMergeResult merge(
    String accountId,
    List<NotificationItem> fetched, {
    String? cursor,
  }) {
    final stamped = fetched
        .map((n) => n.accountId == accountId
            ? n
            : n.copyWith(accountId: accountId))
        .toList();

    final existing = _cache[accountId];
    if (existing == null || existing.notifications.isEmpty) {
      final list = _dedupByEventKey(stamped)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _cache[accountId] = _AccountNotifications(list, cursor);
      return NotificationMergeResult(
        newCount: list.length,
        updatedCount: 0,
      );
    }

    final byKey = <String, NotificationItem>{
      for (final n in existing.notifications) _eventKey(n): n,
    };

    int newCount = 0;
    int updatedCount = 0;
    for (final n in stamped) {
      final key = _eventKey(n);
      final old = byKey[key];
      if (old == null) {
        existing.notifications.add(n);
        byKey[key] = n;
        newCount++;
      } else {
        final isNewerTime = n.timestamp.isAfter(old.timestamp);
        final hasMoreActors = n.totalActorCount > old.totalActorCount;
        if (isNewerTime || hasMoreActors) {
          final idx = existing.notifications.indexOf(old);
          if (idx >= 0) existing.notifications[idx] = n;
          byKey[key] = n;
          updatedCount++;
        }
      }
    }

    // ソート＋保険の重複除去
    existing.notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _removeDuplicatesInPlace(existing.notifications);

    if (cursor != null) existing.cursor = cursor;
    return NotificationMergeResult(
      newCount: newCount,
      updatedCount: updatedCount,
    );
  }

  /// loadMore 結果を末尾に追加（eventKey ベースで重複排除、末尾追加後に全体ソート）
  void append(String accountId, List<NotificationItem> items, String? cursor) {
    final existing = _cache[accountId];
    if (existing == null) {
      _cache[accountId] = _AccountNotifications(
          _dedupByEventKey(items)
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
          cursor);
      return;
    }
    final existingKeys = <String>{
      for (final n in existing.notifications) _eventKey(n),
    };
    final newItems =
        items.where((n) => !existingKeys.contains(_eventKey(n))).toList();
    existing.notifications.addAll(newItems);
    existing.notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _removeDuplicatesInPlace(existing.notifications);
    if (cursor != null) existing.cursor = cursor;
  }

  /// 同じ eventKey の要素を先頭優先で除去した新リストを返す
  List<NotificationItem> _dedupByEventKey(List<NotificationItem> items) {
    final seen = <String>{};
    final result = <NotificationItem>[];
    for (final n in items) {
      final key = _eventKey(n);
      if (seen.add(key)) result.add(n);
    }
    return result;
  }

  /// in-place で eventKey の重複を除去（先に現れたものを残す）
  void _removeDuplicatesInPlace(List<NotificationItem> items) {
    final seen = <String>{};
    items.removeWhere((n) {
      final key = _eventKey(n);
      if (seen.contains(key)) {
        debugPrint('[NotifCache] Removed duplicate eventKey=$key id=${n.id}');
        return true;
      }
      seen.add(key);
      return false;
    });
  }

  // ──────────── ハイライト判定 ────────────

  /// 通知が未見か（= ハイライト対象）
  bool isNew(NotificationItem n) {
    final seen = _seenAt[_eventKey(n)];
    if (seen == null) return true;
    return n.timestamp.isAfter(seen);
  }

  /// 通知を「見た」ことにする（ハイライト発火と同時に呼ぶ）
  void markSeen(NotificationItem n) {
    _seenAt[_eventKey(n)] = DateTime.now();
    _persistSeenAt();
  }

  /// アカウントに未見の通知があるか（バッジ用）
  bool hasUnseenFor(String accountId) {
    for (final n in get(accountId)) {
      if (isNew(n)) return true;
    }
    return false;
  }

  /// 直近のフェッチ時刻（pull / 自動 / バックグラウンドの全経路で記録）。
  /// クールダウン判定で「同じアカウントを連続フェッチしない」のために使う。
  final Map<String, DateTime> _lastFetchAt = {};

  void recordFetch(String accountId) {
    _lastFetchAt[accountId] = DateTime.now();
  }

  DateTime? getLastFetchAt(String accountId) => _lastFetchAt[accountId];

  bool isInCooldown(String accountId, Duration cooldown) {
    final last = _lastFetchAt[accountId];
    if (last == null) return false;
    return DateTime.now().difference(last) < cooldown;
  }

  /// アカウント単位の未見件数（バッジに数字を出すため）
  int unseenCountFor(String accountId) {
    var count = 0;
    for (final n in get(accountId)) {
      if (isNew(n)) count++;
    }
    return count;
  }

  /// 全有効アカウントのうち未見がある accountId 集合
  Set<String> unseenAccountIds(List<String> accountIds) {
    return {
      for (final id in accountIds)
        if (hasUnseenFor(id)) id,
    };
  }

  /// 全有効アカウントの未見件数 Map
  Map<String, int> unseenCounts(List<String> accountIds) {
    return {
      for (final id in accountIds) id: unseenCountFor(id),
    };
  }

  // ──────────── 永続化 ────────────

  /// 起動時に呼ぶ: 保存された seenAt を復元
  Future<void> loadSeenAt() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('notif_seen_at');
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        for (final e in map.entries) {
          final ms = e.value;
          if (ms is int) {
            _seenAt[e.key] = DateTime.fromMillisecondsSinceEpoch(ms);
          }
        }
      } catch (e) {
        debugPrint('[NotifCache] Failed to load seenAt: $e');
      }
    }
    // 旧仕様の notif_read_line_* キーをクリーンアップ
    final legacyKeys =
        prefs.getKeys().where((k) => k.startsWith('notif_read_line_')).toList();
    for (final key in legacyKeys) {
      await prefs.remove(key);
    }
  }

  /// seenAt マップが肥大化するので定期的に剪定（1000件超えたら古い500件を削除）
  void _pruneSeenAtIfNeeded() {
    if (_seenAt.length <= 1000) return;
    final entries = _seenAt.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (var i = 0; i < entries.length - 500; i++) {
      _seenAt.remove(entries[i].key);
    }
  }

  DateTime? _lastPersist;
  Future<void> _persistSeenAt() async {
    _pruneSeenAtIfNeeded();
    // 連続呼び出しを抑制（500ms デバウンス的挙動）
    final now = DateTime.now();
    if (_lastPersist != null &&
        now.difference(_lastPersist!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastPersist = now;
    final prefs = await SharedPreferences.getInstance();
    final map = {
      for (final e in _seenAt.entries) e.key: e.value.millisecondsSinceEpoch,
    };
    await prefs.setString('notif_seen_at', jsonEncode(map));
  }

  /// 全アカウントの通知を時系列でマージして返す
  List<NotificationItem> getAllMerged(List<String> accountIds) {
    final all = <NotificationItem>[];
    // account_id 重複に備えて Set 経由で
    for (final id in accountIds.toSet()) {
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
