import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/notification_item.dart';
import 'package:mobile_omniverse/models/sns_service.dart';

/// notifications_screen.dart の公開テスト可能な部分のテスト
///
/// fetchAccountNotifications と _NotificationFetchResult はファイル内で
/// プライベートまたは外部サービス依存のため、ここでは
/// 通知のモデルとソートロジックを検証する。
void main() {
  group('NotificationItem sorting (timestamp descending)', () {
    test('notifications sort by timestamp descending', () {
      final items = [
        _makeNotification(id: 'n1', timestamp: DateTime(2024, 1, 10)),
        _makeNotification(id: 'n3', timestamp: DateTime(2024, 1, 12)),
        _makeNotification(id: 'n2', timestamp: DateTime(2024, 1, 11)),
      ];
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      expect(items[0].id, 'n3');
      expect(items[1].id, 'n2');
      expect(items[2].id, 'n1');
    });
  });

  group('NotificationItem deduplication by id', () {
    test('retainWhere with seen set removes duplicates', () {
      final items = [
        _makeNotification(id: 'n1', timestamp: DateTime(2024, 1, 10)),
        _makeNotification(id: 'n1', timestamp: DateTime(2024, 1, 10)),
        _makeNotification(id: 'n2', timestamp: DateTime(2024, 1, 11)),
        _makeNotification(id: 'n2', timestamp: DateTime(2024, 1, 11)),
        _makeNotification(id: 'n3', timestamp: DateTime(2024, 1, 12)),
      ];
      final seen = <String>{};
      items.retainWhere((n) => seen.add(n.id));

      expect(items.length, 3);
      expect(items.map((n) => n.id).toList(), ['n1', 'n2', 'n3']);
    });
  });

  group('NotificationItem merge and deduplicate + sort', () {
    test('merged list deduplicates and sorts correctly', () {
      // Simulates the REST + GraphQL merge logic from fetchAccountNotifications
      final restNotifications = [
        _makeNotification(id: 'r1', timestamp: DateTime(2024, 1, 15)),
        _makeNotification(id: 'common', timestamp: DateTime(2024, 1, 14)),
      ];
      final gqlNotifications = [
        _makeNotification(id: 'common', timestamp: DateTime(2024, 1, 14)),
        _makeNotification(id: 'g1', timestamp: DateTime(2024, 1, 13)),
      ];

      final merged = [...restNotifications, ...gqlNotifications];
      final seen = <String>{};
      merged.retainWhere((n) => seen.add(n.id));
      merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      expect(merged.length, 3);
      expect(merged[0].id, 'r1');     // Jan 15 (newest)
      expect(merged[1].id, 'common'); // Jan 14
      expect(merged[2].id, 'g1');     // Jan 13 (oldest)
    });
  });

  group('NotificationType', () {
    test('all expected types exist', () {
      expect(NotificationType.values, contains(NotificationType.like));
      expect(NotificationType.values, contains(NotificationType.repost));
      expect(NotificationType.values, contains(NotificationType.reply));
      expect(NotificationType.values, contains(NotificationType.follow));
      expect(NotificationType.values, contains(NotificationType.mention));
      expect(NotificationType.values, contains(NotificationType.quote));
      expect(NotificationType.values, contains(NotificationType.unknown));
    });

    test('typeLabel returns Japanese labels', () {
      final item = _makeNotification(type: NotificationType.like);
      expect(item.typeLabel, 'いいね');
    });

    test('typeLabel for repost', () {
      final item = _makeNotification(type: NotificationType.repost);
      expect(item.typeLabel, 'リポスト');
    });

    test('typeLabel for reply', () {
      final item = _makeNotification(type: NotificationType.reply);
      expect(item.typeLabel, 'リプライ');
    });

    test('typeLabel for mention', () {
      final item = _makeNotification(type: NotificationType.mention);
      expect(item.typeLabel, 'メンション');
    });

    test('typeLabel for quote', () {
      final item = _makeNotification(type: NotificationType.quote);
      expect(item.typeLabel, '引用');
    });

    test('typeLabel for follow', () {
      final item = _makeNotification(type: NotificationType.follow);
      expect(item.typeLabel, 'フォロー');
    });

    test('typeLabel for unknown', () {
      final item = _makeNotification(type: NotificationType.unknown);
      expect(item.typeLabel, '通知');
    });
  });

  group('NotificationItem.totalActorCount', () {
    test('returns 1 when no additional actors', () {
      final item = _makeNotification();
      expect(item.totalActorCount, 1);
    });

    test('returns correct count with additional actors', () {
      final item = NotificationItem(
        id: 'n1',
        type: NotificationType.like,
        source: SnsService.x,
        actorName: 'Main Actor',
        actorHandle: '@main',
        timestamp: DateTime(2024, 1, 15),
        additionalActors: [
          const NotificationActor(name: 'Actor 2', handle: '@actor2'),
          const NotificationActor(name: 'Actor 3', handle: '@actor3'),
        ],
      );
      expect(item.totalActorCount, 3);
    });
  });

  group('NotificationItem.copyWith', () {
    test('updates targetPostBody', () {
      final original = _makeNotification(targetPostBody: 'original text');
      final copied = original.copyWith(targetPostBody: 'updated text');
      expect(copied.targetPostBody, 'updated text');
      expect(copied.id, original.id);
      expect(copied.type, original.type);
    });

    test('updates accountId', () {
      final original = _makeNotification();
      final copied = original.copyWith(accountId: 'new_account');
      expect(copied.accountId, 'new_account');
    });

    test('preserves other fields when not specified', () {
      final original = _makeNotification(
        id: 'n1',
        type: NotificationType.repost,
        targetPostBody: 'body',
      );
      final copied = original.copyWith(accountId: 'acc_1');
      expect(copied.id, 'n1');
      expect(copied.type, NotificationType.repost);
      expect(copied.targetPostBody, 'body');
    });
  });
}

/// テスト用 NotificationItem ファクトリ
NotificationItem _makeNotification({
  String id = 'notif_1',
  NotificationType type = NotificationType.like,
  SnsService source = SnsService.x,
  String actorName = 'Test User',
  String actorHandle = '@testuser',
  DateTime? timestamp,
  String? targetPostBody,
  String? targetPostId,
  String? accountId,
}) {
  return NotificationItem(
    id: id,
    type: type,
    source: source,
    actorName: actorName,
    actorHandle: actorHandle,
    timestamp: timestamp ?? DateTime(2024, 1, 15, 12, 0, 0),
    targetPostBody: targetPostBody,
    targetPostId: targetPostId,
    accountId: accountId,
  );
}
