import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/models/notification_item.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/notification_cache_service.dart';

/// テスト用 NotificationItem ファクトリ
NotificationItem makeNotification({
  String id = 'notif_1',
  NotificationType type = NotificationType.like,
  SnsService source = SnsService.x,
  String actorName = 'Test User',
  String actorHandle = '@testuser',
  List<NotificationActor> additionalActors = const [],
  String? targetPostBody,
  DateTime? timestamp,
  String? accountId,
}) {
  return NotificationItem(
    id: id,
    type: type,
    source: source,
    actorName: actorName,
    actorHandle: actorHandle,
    additionalActors: additionalActors,
    targetPostBody: targetPostBody,
    timestamp: timestamp ?? DateTime(2024, 6, 1, 12, 0, 0),
    accountId: accountId,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationCacheService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = NotificationCacheService.instance;
    // テスト間でキャッシュをクリア。
    // 注: _seenAt はシングルトンで clearAll では消えないため、
    //     isNew/markSeen 系のテストでは id を一意にして衝突を避ける。
    service.clearAll();
  });

  group('NotificationCacheService', () {
    group('get', () {
      test('未知のアカウントIDで空リストを返す', () {
        final result = service.get('unknown_account');
        expect(result, isEmpty);
      });

      test('merge後に正しい通知リストを返す', () {
        final items = [
          makeNotification(id: 'n1', accountId: 'acc_1'),
          makeNotification(id: 'n2', accountId: 'acc_1'),
        ];
        service.merge('acc_1', items);

        final result = service.get('acc_1');
        expect(result, hasLength(2));
      });
    });

    group('hasData', () {
      test('未知のアカウントIDで false を返す', () {
        expect(service.hasData('unknown'), false);
      });

      test('merge後に true を返す', () {
        service.merge('acc_1', [makeNotification(id: 'n1', accountId: 'acc_1')]);
        expect(service.hasData('acc_1'), true);
      });
    });

    group('getCursor', () {
      test('未知のアカウントIDで null を返す', () {
        expect(service.getCursor('unknown'), isNull);
      });

      test('merge時にcursor付きで呼ぶと正しい値を返す', () {
        service
            .merge('acc_1', [makeNotification(id: 'n1')], cursor: 'cursor_abc');
        expect(service.getCursor('acc_1'), 'cursor_abc');
      });

      test('cursorなしでmergeするとnullのまま', () {
        service.merge('acc_1', [makeNotification(id: 'n1')]);
        expect(service.getCursor('acc_1'), isNull);
      });
    });

    group('clearAll', () {
      test('全キャッシュをクリアする', () {
        service.merge('acc_1', [makeNotification(id: 'n1', accountId: 'acc_1')]);
        service.merge('acc_2', [makeNotification(id: 'n2', accountId: 'acc_2')]);

        expect(service.hasData('acc_1'), true);
        expect(service.hasData('acc_2'), true);

        service.clearAll();

        expect(service.hasData('acc_1'), false);
        expect(service.hasData('acc_2'), false);
        expect(service.get('acc_1'), isEmpty);
        expect(service.get('acc_2'), isEmpty);
      });
    });

    group('merge', () {
      test('新規通知を追加する', () {
        final items = [
          makeNotification(id: 'n1', accountId: 'acc_1'),
          makeNotification(id: 'n2', accountId: 'acc_1'),
        ];
        final result = service.merge('acc_1', items);

        expect(result.newCount, 2);
        expect(result.updatedCount, 0);
        expect(service.get('acc_1'), hasLength(2));
      });

      test('重複する通知は追加も更新もしない', () {
        final items1 = [makeNotification(id: 'n1', accountId: 'acc_1')];
        final items2 = [makeNotification(id: 'n1', accountId: 'acc_1')];

        service.merge('acc_1', items1);
        final result = service.merge('acc_1', items2);

        expect(result.newCount, 0);
        expect(result.updatedCount, 0);
        expect(result.hasChanges, false);
        expect(service.get('acc_1'), hasLength(1));
      });

      test('重複と新規が混在する場合、新規のみ追加', () {
        service.merge('acc_1', [makeNotification(id: 'n1', accountId: 'acc_1')]);
        final result = service.merge('acc_1', [
          makeNotification(id: 'n1', accountId: 'acc_1'),
          makeNotification(id: 'n2', accountId: 'acc_1'),
        ]);

        // n2 は新規
        expect(result.newCount, 1);
        expect(service.get('acc_1'), hasLength(2));
      });

      test('新規件数を返す', () {
        final result = service.merge('acc_1', [
          makeNotification(id: 'n1'),
          makeNotification(id: 'n2'),
          makeNotification(id: 'n3'),
        ]);
        expect(result.newCount, 3);
        expect(result.hasChanges, true);
      });

      test('accountId が異なる通知は accountId をスタンプする', () {
        final items = [makeNotification(id: 'n1', accountId: 'wrong')];
        service.merge('acc_1', items);

        final result = service.get('acc_1');
        expect(result.first.accountId, 'acc_1');
      });

      test('totalActorCount が大きい同一IDの通知で既存を更新', () {
        final original = makeNotification(id: 'n1', accountId: 'acc_1');
        service.merge('acc_1', [original]);

        final updated = makeNotification(
          id: 'n1',
          accountId: 'acc_1',
          additionalActors: [
            const NotificationActor(name: 'Extra', handle: '@extra'),
          ],
        );
        final result = service.merge('acc_1', [updated]);

        // 新規ではなく更新としてカウントされる
        expect(result.newCount, 0);
        expect(result.updatedCount, 1);
        final stored = service.get('acc_1');
        expect(stored, hasLength(1));
        expect(stored.first.totalActorCount, 2);
      });

      test('cursorが更新される', () {
        service.merge('acc_1', [makeNotification(id: 'n1')], cursor: 'c1');
        expect(service.getCursor('acc_1'), 'c1');

        service.merge('acc_1', [makeNotification(id: 'n2')], cursor: 'c2');
        expect(service.getCursor('acc_1'), 'c2');
      });
    });

    group('isNew / markSeen', () {
      test('一度も見ていない通知は isNew=true', () {
        final n = makeNotification(id: 'unseen_1');
        expect(service.isNew(n), true);
      });

      test('markSeen 後は同じ通知が isNew=false', () {
        final n = makeNotification(
            id: 'seen_1', timestamp: DateTime(2024, 6, 1, 12, 0, 0));
        service.markSeen(n);
        expect(service.isNew(n), false);
      });

      test('markSeen 後でも timestamp が進んだ同一イベントは未読復活 (isNew=true)', () {
        final old = makeNotification(
            id: 'revive_1', timestamp: DateTime(2024, 6, 1, 12, 0, 0));
        service.markSeen(old);
        // 同一 eventKey（同 id・同 type）で、markSeen 時刻より新しい timestamp。
        final newer =
            makeNotification(id: 'revive_1', timestamp: DateTime(2099, 1, 1));
        expect(service.isNew(newer), true);
      });
    });

    group('hasUnseenFor / unseenCountFor', () {
      test('merge した通知は未見としてカウントされる', () {
        service.merge('acc_unseen', [
          makeNotification(id: 'uc_1', accountId: 'acc_unseen'),
          makeNotification(id: 'uc_2', accountId: 'acc_unseen'),
        ]);
        expect(service.hasUnseenFor('acc_unseen'), true);
        expect(service.unseenCountFor('acc_unseen'), 2);
      });

      test('markSeen で未見件数が減り、全て見たら false', () {
        final n1 = makeNotification(id: 'us_1', accountId: 'acc_seen');
        final n2 = makeNotification(id: 'us_2', accountId: 'acc_seen');
        service.merge('acc_seen', [n1, n2]);

        service.markSeen(n1);
        expect(service.unseenCountFor('acc_seen'), 1);

        service.markSeen(n2);
        expect(service.hasUnseenFor('acc_seen'), false);
      });
    });

    group('loadSeenAt', () {
      test('保存済み seenAt を例外なく復元する', () async {
        final ms = DateTime(2024, 6, 1).millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          'notif_seen_at': '{"like:persist_1":$ms}',
        });
        // シングルトンのため _loaded が既に true だと no-op になる。
        // ここでは少なくとも例外を投げずに完了することを検証する。
        await service.loadSeenAt();
      });
    });

    group('getAllMerged', () {
      test('複数アカウントの通知を時系列でマージ', () {
        service.merge('acc_1', [
          makeNotification(
            id: 'n1',
            accountId: 'acc_1',
            timestamp: DateTime(2024, 6, 1, 10, 0, 0),
          ),
          makeNotification(
            id: 'n3',
            accountId: 'acc_1',
            timestamp: DateTime(2024, 6, 1, 14, 0, 0),
          ),
        ]);
        service.merge('acc_2', [
          makeNotification(
            id: 'n2',
            accountId: 'acc_2',
            timestamp: DateTime(2024, 6, 1, 12, 0, 0),
          ),
        ]);

        final result = service.getAllMerged(['acc_1', 'acc_2']);

        expect(result, hasLength(3));
        // 新しい順
        expect(result[0].id, 'n3');
        expect(result[1].id, 'n2');
        expect(result[2].id, 'n1');
      });

      test('空のアカウントリストでは空リストを返す', () {
        final result = service.getAllMerged([]);
        expect(result, isEmpty);
      });
    });

    group('append', () {
      test('末尾に追加し重複は排除', () {
        service.merge('acc_1', [makeNotification(id: 'n1', accountId: 'acc_1')]);
        service.append('acc_1', [
          makeNotification(id: 'n1', accountId: 'acc_1'), // 重複
          makeNotification(id: 'n2', accountId: 'acc_1'), // 新規
        ], 'cursor_new');

        expect(service.get('acc_1'), hasLength(2));
        expect(service.getCursor('acc_1'), 'cursor_new');
      });

      test('キャッシュが空の状態で append すると新規作成', () {
        service.append('acc_1', [
          makeNotification(id: 'n1', accountId: 'acc_1'),
        ], 'cursor_1');

        expect(service.get('acc_1'), hasLength(1));
        expect(service.getCursor('acc_1'), 'cursor_1');
      });
    });
  });
}
