import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/notification_item.dart';
import 'package:mobile_omniverse/models/sns_service.dart';

void main() {
  group('NotificationItem', () {
    NotificationItem makeNotification({
      String id = 'notif_1',
      NotificationType type = NotificationType.like,
      SnsService source = SnsService.x,
      String actorName = 'Test User',
      String actorHandle = '@testuser',
      String? actorAvatarUrl,
      List<NotificationActor> additionalActors = const [],
      String? targetPostBody,
      String? targetPostId,
      DateTime? timestamp,
      bool isRead = false,
      String? accountId,
    }) {
      return NotificationItem(
        id: id,
        type: type,
        source: source,
        actorName: actorName,
        actorHandle: actorHandle,
        actorAvatarUrl: actorAvatarUrl,
        additionalActors: additionalActors,
        targetPostBody: targetPostBody,
        targetPostId: targetPostId,
        timestamp: timestamp ?? DateTime(2024, 6, 1, 12, 0, 0),
        isRead: isRead,
        accountId: accountId,
      );
    }

    test('コンストラクタで正しいフィールドが設定される', () {
      final ts = DateTime(2024, 6, 1, 12, 0, 0);
      final item = NotificationItem(
        id: 'n1',
        type: NotificationType.like,
        source: SnsService.x,
        actorName: 'Alice',
        actorHandle: '@alice',
        actorAvatarUrl: 'https://example.com/avatar.jpg',
        targetPostBody: 'Hello world',
        targetPostId: 'post_1',
        timestamp: ts,
        isRead: true,
        accountId: 'acc_1',
      );

      expect(item.id, 'n1');
      expect(item.type, NotificationType.like);
      expect(item.source, SnsService.x);
      expect(item.actorName, 'Alice');
      expect(item.actorHandle, '@alice');
      expect(item.actorAvatarUrl, 'https://example.com/avatar.jpg');
      expect(item.targetPostBody, 'Hello world');
      expect(item.targetPostId, 'post_1');
      expect(item.timestamp, ts);
      expect(item.isRead, true);
      expect(item.accountId, 'acc_1');
    });

    test('デフォルトのオプション値が正しい', () {
      final item = NotificationItem(
        id: 'n2',
        type: NotificationType.follow,
        source: SnsService.bluesky,
        actorName: 'Bob',
        actorHandle: '@bob',
        timestamp: DateTime(2024, 1, 1),
      );

      expect(item.actorAvatarUrl, isNull);
      expect(item.additionalActors, isEmpty);
      expect(item.targetPostBody, isNull);
      expect(item.targetPostId, isNull);
      expect(item.isRead, false);
      expect(item.accountId, isNull);
    });

    test('totalActorCount はメインアクター + additionalActors の合計', () {
      final item = makeNotification(
        additionalActors: [
          const NotificationActor(name: 'User2', handle: '@user2'),
          const NotificationActor(name: 'User3', handle: '@user3'),
        ],
      );

      expect(item.totalActorCount, 3);
    });

    test('totalActorCount は additionalActors が空なら 1', () {
      final item = makeNotification();
      expect(item.totalActorCount, 1);
    });

    group('typeLabel', () {
      test('like → いいね', () {
        expect(makeNotification(type: NotificationType.like).typeLabel, 'いいね');
      });

      test('repost → リポスト', () {
        expect(makeNotification(type: NotificationType.repost).typeLabel, 'リポスト');
      });

      test('reply → リプライ', () {
        expect(makeNotification(type: NotificationType.reply).typeLabel, 'リプライ');
      });

      test('follow → フォロー', () {
        expect(makeNotification(type: NotificationType.follow).typeLabel, 'フォロー');
      });

      test('mention → メンション', () {
        expect(makeNotification(type: NotificationType.mention).typeLabel, 'メンション');
      });

      test('quote → 引用', () {
        expect(makeNotification(type: NotificationType.quote).typeLabel, '引用');
      });

      test('unknown → 通知', () {
        expect(makeNotification(type: NotificationType.unknown).typeLabel, '通知');
      });

      test('全 NotificationType にラベルが存在する', () {
        for (final type in NotificationType.values) {
          final item = makeNotification(type: type);
          expect(item.typeLabel, isNotEmpty,
              reason: '$type にラベルがありません');
        }
      });
    });

    group('copyWith', () {
      test('targetPostBody を変更', () {
        final original = makeNotification(targetPostBody: 'original');
        final copied = original.copyWith(targetPostBody: 'updated');

        expect(copied.targetPostBody, 'updated');
        // 他のフィールドは変わらない
        expect(copied.id, original.id);
        expect(copied.type, original.type);
        expect(copied.actorName, original.actorName);
        expect(copied.actorHandle, original.actorHandle);
        expect(copied.timestamp, original.timestamp);
        expect(copied.accountId, original.accountId);
      });

      test('accountId を変更', () {
        final original = makeNotification(accountId: 'acc_old');
        final copied = original.copyWith(accountId: 'acc_new');

        expect(copied.accountId, 'acc_new');
        expect(copied.id, original.id);
        expect(copied.targetPostBody, original.targetPostBody);
      });

      test('引数なしで copyWith すると同じ値が保持される', () {
        final original = makeNotification(
          targetPostBody: 'body',
          accountId: 'acc_1',
        );
        final copied = original.copyWith();

        expect(copied.id, original.id);
        expect(copied.type, original.type);
        expect(copied.source, original.source);
        expect(copied.actorName, original.actorName);
        expect(copied.actorHandle, original.actorHandle);
        expect(copied.actorAvatarUrl, original.actorAvatarUrl);
        expect(copied.additionalActors, original.additionalActors);
        expect(copied.targetPostBody, original.targetPostBody);
        expect(copied.targetPostId, original.targetPostId);
        expect(copied.timestamp, original.timestamp);
        expect(copied.isRead, original.isRead);
        expect(copied.accountId, original.accountId);
      });

      test('copyWith で両方のフィールドを同時に変更', () {
        final original = makeNotification(
          targetPostBody: 'old body',
          accountId: 'old_acc',
        );
        final copied = original.copyWith(
          targetPostBody: 'new body',
          accountId: 'new_acc',
        );

        expect(copied.targetPostBody, 'new body');
        expect(copied.accountId, 'new_acc');
      });
    });
  });

  group('NotificationActor', () {
    test('コンストラクタで正しいフィールドが設定される', () {
      const actor = NotificationActor(
        name: 'Alice',
        handle: '@alice',
        avatarUrl: 'https://example.com/avatar.jpg',
      );

      expect(actor.name, 'Alice');
      expect(actor.handle, '@alice');
      expect(actor.avatarUrl, 'https://example.com/avatar.jpg');
    });

    test('avatarUrl はオプショナルで null がデフォルト', () {
      const actor = NotificationActor(name: 'Bob', handle: '@bob');
      expect(actor.avatarUrl, isNull);
    });
  });

  group('NotificationType', () {
    test('全ての値が定義されている', () {
      expect(NotificationType.values, containsAll([
        NotificationType.like,
        NotificationType.repost,
        NotificationType.reply,
        NotificationType.follow,
        NotificationType.mention,
        NotificationType.quote,
        NotificationType.unknown,
      ]));
    });
  });
}
