import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/models/follow_user.dart';
import 'package:mobile_omniverse/models/post.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/follow_db.dart';
import 'package:mobile_omniverse/services/user_detail_service.dart';
import 'package:mobile_omniverse/services/x_api_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_data.dart';

void main() {
  final db = FollowDb.instance;
  final svc = UserDetailService.instance;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    db.factoryOverride = databaseFactoryFfi;
    db.pathOverride = inMemoryDatabasePath;
    // 実時間で待つと試験が遅いだけなので、間隔は置かない
    svc.interval = Duration.zero;
  });

  tearDown(() async {
    await db.close();
    db.factoryOverride = null;
    db.pathOverride = null;
  });

  final account = Account(
    id: 'acc',
    service: SnsService.x,
    displayName: 'Me',
    handle: '@me',
    credentials: const XCredentials(authToken: 'tok', ct0: 'ct0'),
    createdAt: DateTime(2026),
  );

  Future<void> following(List<String> ids) async {
    final id = await db.startSnapshot(
        service: SnsService.x, targetHandle: 'me', kind: 'following');
    await db.addBatch(
        snapshotId: id,
        users: [
          for (final i in ids)
            FollowUser(restId: i, screenName: 'user$i', name: 'U$i'),
        ],
        cursor: '0|end');
    await db.finishSnapshot(snapshotId: id, completed: true, reason: 'end');
  }

  Map<String, dynamic> profileWith({int? month, int? day, int? year}) => {
        'rest_id': '1',
        if (month != null)
          'legacy_extended_profile': {
            'birthdate': {
              'day': day,
              'month': month,
              'year': ?year,
              'visibility': 'Public',
            },
          },
      };

  group('読み取り', () {
    test('誕生日は legacy_extended_profile.birthdate から', () {
      expect(UserDetailService.parseBirthdate(profileWith(month: 4, day: 6)),
          (month: 4, day: 6, year: null));
      expect(
          UserDetailService.parseBirthdate(
              profileWith(month: 4, day: 6, year: 1990)),
          (month: 4, day: 6, year: 1990));
    });

    test('項目が無ければ非公開か未設定として null', () {
      expect(UserDetailService.parseBirthdate(profileWith()), isNull);
      expect(UserDetailService.parseBirthdate(null), isNull);
      expect(
          UserDetailService.parseBirthdate(
              {'legacy_extended_profile': {'birthdate': {'month': 4}}}),
          isNull);
    });

    test('最近の投稿はリポスト込みと自分の投稿だけを分ける', () {
      final posts = [
        makePost(id: 'a', timestamp: DateTime(2026, 9, 1)),
        makePost(id: 'b', timestamp: DateTime(2026, 10, 1), isRetweet: true),
        // 固定投稿は先頭に古いものが来る
        makePost(id: 'c', timestamp: DateTime(2020, 1, 1)),
      ];
      expect(UserDetailService.summarizePosts(posts),
          (last: DateTime(2026, 10, 1), lastOwn: DateTime(2026, 9, 1)));
      expect(UserDetailService.summarizePosts(const <Post>[]),
          (last: null, lastOwn: null));
    });
  });

  group('取得', () {
    test('起点の人を 1 人ずつ調べて保存する', () async {
      await following(['1', '2']);
      final asked = <String>[];
      svc.fetchProfile = (_, screenName) async {
        asked.add(screenName);
        return profileWith(month: 5, day: 10);
      };
      svc.fetchTimeline = (_, restId, count) async => (
            posts: [makePost(id: restId, timestamp: DateTime(2026, 9, 1))],
            cursor: null,
          );

      final n = await svc.start(
        account: account,
        service: SnsService.x,
        handle: 'me',
        origin: 'following',
        wantBirthday: true,
        wantLastPost: true,
      );
      expect(n, 2);
      expect(asked, ['user1', 'user2']);
      expect(svc.isRunning, isFalse);

      final d = (await db.userDetail('1'))!;
      expect(d.birthMonth, 5);
      expect(d.lastPostAt, DateTime(2026, 9, 1));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('調べ終わった人は次回は飛ばす', () async {
      await following(['1']);
      var calls = 0;
      svc.fetchProfile = (_, _) async {
        calls++;
        return profileWith(month: 1, day: 1);
      };
      Future<int> run() => svc.start(
            account: account,
            service: SnsService.x,
            handle: 'me',
            origin: 'following',
            wantBirthday: true,
            wantLastPost: false,
          );
      expect(await run(), 1);
      expect(await run(), 0);
      expect(calls, 1);
    });

    test('失敗した人は理由を残して次へ進む', () async {
      await following(['1', '2']);
      svc.fetchProfile = (_, screenName) async {
        if (screenName == 'user1') throw Exception('鍵アカウント');
        return profileWith(month: 2, day: 2);
      };
      await svc.start(
        account: account,
        service: SnsService.x,
        handle: 'me',
        origin: 'following',
        wantBirthday: true,
        wantLastPost: false,
      );
      expect((await db.userDetail('1'))!.error, contains('鍵'));
      expect((await db.userDetail('1'))!.profileFetchedAt, isNotNull);
      expect((await db.userDetail('2'))!.birthMonth, 2);
    });

    test('制限に当たったら待って同じ人をやり直す', () async {
      await following(['1']);
      var calls = 0;
      svc.fetchProfile = (_, _) async {
        calls++;
        if (calls == 1) {
          throw XRateLimitException(
              'UserByScreenName', const Duration(milliseconds: 50));
        }
        return profileWith(month: 3, day: 3);
      };
      await svc.start(
        account: account,
        service: SnsService.x,
        handle: 'me',
        origin: 'following',
        wantBirthday: true,
        wantLastPost: false,
      );
      expect(calls, 2);
      expect((await db.userDetail('1'))!.birthMonth, 3);
    });

    test('認証が切れたら止める', () async {
      await following(['1', '2']);
      var calls = 0;
      svc.fetchProfile = (_, _) async {
        calls++;
        throw XAuthException('expired');
      };
      await svc.start(
        account: account,
        service: SnsService.x,
        handle: 'me',
        origin: 'following',
        wantBirthday: true,
        wantLastPost: false,
      );
      expect(calls, 1);
      expect(await db.userDetail('1'), isNull);
    });

    test('一覧が無ければ何もしない', () async {
      expect(
          await svc.start(
            account: account,
            service: SnsService.x,
            handle: 'me',
            origin: 'following',
            wantBirthday: true,
            wantLastPost: true,
          ),
          0);
    });
  });
}
