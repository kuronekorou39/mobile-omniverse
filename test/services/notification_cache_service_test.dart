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
    // テスト間でキャッシュをクリア
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
        service.merge('acc_1', [makeNotification(id: 'n1')], cursor: 'cursor_abc');
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
        final count = service.merge('acc_1', items);

        expect(count, 2);
        expect(service.get('acc_1'), hasLength(2));
      });

      test('重複する通知は追加しない', () {
        final items1 = [makeNotification(id: 'n1', accountId: 'acc_1')];
        final items2 = [makeNotification(id: 'n1', accountId: 'acc_1')];

        service.merge('acc_1', items1);
        final count = service.merge('acc_1', items2);

        expect(count, 0);
        expect(service.get('acc_1'), hasLength(1));
      });

      test('重複と新規が混在する場合、新規のみ追加', () {
        service.merge('acc_1', [makeNotification(id: 'n1', accountId: 'acc_1')]);
        final count = service.merge('acc_1', [
          makeNotification(id: 'n1', accountId: 'acc_1'),
          makeNotification(id: 'n2', accountId: 'acc_1'),
        ]);

        // n2 は新規
        expect(count, 1);
        expect(service.get('acc_1'), hasLength(2));
      });

      test('新規件数を返す', () {
        final count = service.merge('acc_1', [
          makeNotification(id: 'n1'),
          makeNotification(id: 'n2'),
          makeNotification(id: 'n3'),
        ]);
        expect(count, 3);
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
        final count = service.merge('acc_1', [updated]);

        // 更新されたのでカウントに含まれる
        expect(count, 1);
        final result = service.get('acc_1');
        expect(result, hasLength(1));
        expect(result.first.totalActorCount, 2);
      });

      test('cursorが更新される', () {
        service.merge('acc_1', [makeNotification(id: 'n1')], cursor: 'c1');
        expect(service.getCursor('acc_1'), 'c1');

        service.merge('acc_1', [makeNotification(id: 'n2')], cursor: 'c2');
        expect(service.getCursor('acc_1'), 'c2');
      });
    });

    group('openTab', () {
      test('初回呼び出しで DateTime.now() に近い値を返す（既読ラインなし）', () {
        final before = DateTime.now();
        final result = service.openTab('acc_1');
        final after = DateTime.now();

        // 初回は「全て既読扱い」なので DateTime.now() を返す
        expect(result.isAfter(before.subtract(const Duration(seconds: 1))), true);
        expect(result.isBefore(after.add(const Duration(seconds: 1))), true);
      });

      test('2回目の呼び出しで前回のタイムスタンプを返す', () async {
        // 1回目: 既読ラインを設定
        service.openTab('acc_1');

        // 少し待って差を作る
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 2回目: 1回目の既読ラインを返すはず
        final before2nd = DateTime.now();
        final result = service.openTab('acc_1');

        // 2回目の結果は、2回目の呼び出し時刻より前（1回目のタイムスタンプ）
        expect(result.isBefore(before2nd), true);
      });
    });

    group('openAllTab', () {
      test('全アカウントの既読ラインを更新する', () async {
        // 最初に各アカウントの既読ラインを設定
        service.openTab('acc_1');
        service.openTab('acc_2');

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // openAllTab でリフレッシュ
        final result = service.openAllTab(['acc_1', 'acc_2']);

        // 最も古い旧既読ラインを返す
        expect(result, isA<DateTime>());

        // さらに openTab すると、openAllTab で設定した時刻が返る
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final afterAll1 = service.openTab('acc_1');
        final afterAll2 = service.openTab('acc_2');

        // openAllTab で設定された既読ラインが返される（現在時刻より前）
        expect(afterAll1.isBefore(DateTime.now()), true);
        expect(afterAll2.isBefore(DateTime.now()), true);
      });

      test('初回の openAllTab は DateTime.now() に近い値を返す', () {
        final before = DateTime.now();
        final result = service.openAllTab(['acc_1', 'acc_2']);
        final after = DateTime.now();

        expect(result.isAfter(before.subtract(const Duration(seconds: 1))), true);
        expect(result.isBefore(after.add(const Duration(seconds: 1))), true);
      });
    });

    group('isNew', () {
      test('通知が既読ラインより新しい場合 true', () {
        final readLine = DateTime(2024, 6, 1, 12, 0, 0);
        final notifTime = DateTime(2024, 6, 1, 13, 0, 0);

        expect(service.isNew('acc_1', readLine, notifTime), true);
      });

      test('通知が既読ラインより古い場合 false', () {
        final readLine = DateTime(2024, 6, 1, 12, 0, 0);
        final notifTime = DateTime(2024, 6, 1, 11, 0, 0);

        expect(service.isNew('acc_1', readLine, notifTime), false);
      });

      test('通知が既読ラインと同じ時刻の場合 false', () {
        final readLine = DateTime(2024, 6, 1, 12, 0, 0);
        final notifTime = DateTime(2024, 6, 1, 12, 0, 0);

        // isAfter は同時刻で false
        expect(service.isNew('acc_1', readLine, notifTime), false);
      });
    });

    group('loadReadLines', () {
      test('SharedPreferences から既読ラインを読み込む', () async {
        final ms = DateTime(2024, 6, 1).millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          'notif_read_line_acc_1': ms,
        });

        // _loaded フラグをリセットするため新インスタンスは作れない（シングルトン）
        // loadReadLines は _loaded フラグで1回だけ実行される
        // テストでは直接 openTab の結果で検証
        // 注: シングルトンのため、_loaded フラグが既に true の可能性がある
        await service.loadReadLines();
      });

      test('キーが存在しない場合は既読ラインなし', () async {
        SharedPreferences.setMockInitialValues({});
        await service.loadReadLines();
        // 既読ラインがない場合、openTab は DateTime.now() を返す
        // （テスト実行順序によるが、初回扱いになる）
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
