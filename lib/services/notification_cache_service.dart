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

  /// 同一イベント判定キー
  /// - targetPostId があれば `type:postId` （同じ投稿への複数アクションを集約）
  /// - なければ `type:id` （フォロー等は通知ID単位で独立）
  static String _eventKey(NotificationItem n) => n.targetPostId != null
      ? '${n.type.name}:${n.targetPostId}'
      : '${n.type.name}:${n.id}';

  /// 新規フェッチ結果をマージ
  ///
  /// 同一イベント (type+targetPostId) の既存通知があれば:
  /// - 新データの timestamp が新しい or actor 数が増えていれば上書き
  /// - 最後に timestamp 降順で全体再ソート → 更新された通知が自動的に先頭へ移動
  ///
  /// 同一イベントの既存がなければ新規追加。
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
      final list = List.of(stamped)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _cache[accountId] = _AccountNotifications(list, cursor);
      return NotificationMergeResult(
        newCount: stamped.length,
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

    existing.notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (cursor != null) existing.cursor = cursor;
    return NotificationMergeResult(
      newCount: newCount,
      updatedCount: updatedCount,
    );
  }

  /// loadMore 結果を末尾に追加（eventKey ベースで重複排除）
  void append(String accountId, List<NotificationItem> items, String? cursor) {
    final existing = _cache[accountId];
    if (existing == null) {
      _cache[accountId] = _AccountNotifications(List.of(items), cursor);
      return;
    }
    final existingKeys = <String>{
      for (final n in existing.notifications) _eventKey(n),
    };
    final newItems =
        items.where((n) => !existingKeys.contains(_eventKey(n))).toList();
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
      await prefs.setInt(
          'notif_read_line_$accountId', line.millisecondsSinceEpoch);
    }
  }

  /// 通知が既読ラインより新しいかどうか
  bool isNew(String accountId, DateTime readLine,
          DateTime notificationTimestamp) =>
      notificationTimestamp.isAfter(readLine);

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
