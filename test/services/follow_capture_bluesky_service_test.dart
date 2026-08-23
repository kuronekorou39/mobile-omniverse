import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/models/follow_user.dart';
import 'package:mobile_omniverse/services/bluesky_api_service.dart';
import 'package:mobile_omniverse/services/follow_capture_bluesky_service.dart';
import 'package:mobile_omniverse/services/follow_capture_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_data.dart';

/// 一覧の API は件数を返さないので、getProfiles で埋め直す部分が肝。
/// ここが黙って空振りすると「件数の変化」が全部 0 になる。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final capture = FollowCaptureBlueskyService.instance;
  late _FakeBlueskyApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = _FakeBlueskyApi();
    capture.apiOverride = api;
    capture.reset();
  });

  tearDown(() {
    capture.apiOverride = null;
    capture.reset();
  });

  final account = makeBlueskyAccount(id: 'bsky-1');

  FollowUser listed(String n) => FollowUser(
        restId: 'did:plc:$n',
        screenName: '$n.bsky.social',
        name: 'User $n',
      );

  FollowUser detailed(String n, {int followers = 0, int? posts}) => FollowUser(
        restId: 'did:plc:$n',
        screenName: '$n.bsky.social',
        name: 'User $n',
        followersCount: followers,
        statusesCount: posts,
      );

  Future<FollowListPage> fetch({
    String? cursor,
    FollowListKind kind = FollowListKind.followers,
    CaptureCancelToken? cancelToken,
  }) =>
      capture.fetchPage(
        account: account,
        targetHandle: 'alice.bsky.social',
        kind: kind,
        cursor: cursor,
        cancelToken: cancelToken,
      );

  group('取得', () {
    test('フォロワーとフォローで叩き分ける', () async {
      api.page = (statusCode: 200, users: [listed('a')], cursor: 'c1');

      await fetch(kind: FollowListKind.followers);
      expect(api.followersRequested, isTrue);

      await fetch(kind: FollowListKind.following);
      expect(api.followersRequested, isFalse);
    });

    test('cursor と対象をそのまま渡す', () async {
      api.page = (statusCode: 200, users: const <FollowUser>[], cursor: null);
      await fetch(cursor: 'c1');
      expect(api.lastActor, 'alice.bsky.social');
      expect(api.lastCursor, 'c1');
    });

    test('cursor をそのまま返す', () async {
      api.page = (statusCode: 200, users: [listed('a')], cursor: 'next');
      expect((await fetch()).cursor, 'next');
    });

    test('200 以外はそのまま通す', () async {
      api.page = (statusCode: 429, users: const <FollowUser>[], cursor: null);
      final page = await fetch();
      expect(page.statusCode, 429);
      expect(page.isSuccess, isFalse);
      // 失敗したページで件数を引きにいかない
      expect(api.profileCalls, isEmpty);
    });

    test('JSON でない応答は成功と区別する', () async {
      api.page =
          (statusCode: FollowListPage.badJson, users: const <FollowUser>[], cursor: null);
      expect((await fetch()).statusCode, FollowListPage.badJson);
    });
  });

  group('件数の補完', () {
    test('一覧に無い件数を埋める', () async {
      api.page = (statusCode: 200, users: [listed('a')], cursor: null);
      api.profiles = {'did:plc:a': detailed('a', followers: 42, posts: 7)};

      final page = await fetch();
      expect(page.users.single.followersCount, 42);
      expect(page.users.single.statusesCount, 7);
      // 表示名やアイコンは一覧側の値を保つ
      expect(page.users.single.screenName, 'a.bsky.social');
    });

    test('25 人を超えたら分けて引く', () async {
      final users = [for (var i = 0; i < 60; i++) listed('u$i')];
      api.page = (statusCode: 200, users: users, cursor: null);
      api.profiles = {
        for (final u in users) u.restId: detailed(u.screenName, followers: 1),
      };

      final page = await fetch();
      // getProfiles の上限は 25。60 人なら 25 + 25 + 10
      expect(api.profileCalls.map((c) => c.length), [25, 25, 10]);
      expect(page.users.length, 60);
      expect(page.users.every((u) => u.followersCount == 1), isTrue);
    });

    test('取れなかった相手は一覧の値のまま残す', () async {
      api.page = (statusCode: 200, users: [listed('a'), listed('b')], cursor: null);
      api.profiles = {'did:plc:a': detailed('a', followers: 5)};

      final page = await fetch();
      expect(page.users.first.followersCount, 5);
      // 落とさずに残す。数が減ると取りこぼしに見える
      expect(page.users.last.restId, 'did:plc:b');
      expect(page.users.last.followersCount, 0);
    });

    test('補完が失敗してもページごと落とさない', () async {
      api.page = (statusCode: 200, users: [listed('a')], cursor: 'next');
      api.profilesThrows = Exception('boom');

      final page = await fetch();
      expect(page.isSuccess, isTrue);
      expect(page.users.single.restId, 'did:plc:a');
      expect(page.cursor, 'next');
    });

    test('空ページでは引きにいかない', () async {
      api.page = (statusCode: 200, users: const <FollowUser>[], cursor: null);
      await fetch();
      expect(api.profileCalls, isEmpty);
    });
  });

  group('トークンの期限切れ', () {
    test('401 なら更新して一度だけやり直す', () async {
      api.pages = [
        (statusCode: 401, users: const <FollowUser>[], cursor: null),
        (statusCode: 200, users: [listed('a')], cursor: 'next'),
      ];

      final page = await fetch();
      expect(api.refreshCount, 1);
      expect(page.isSuccess, isTrue);
      expect(page.cursor, 'next');
    });

    test('更新後の資格情報を使う', () async {
      api.pages = [
        (statusCode: 401, users: const <FollowUser>[], cursor: null),
        (statusCode: 200, users: [listed('a')], cursor: null),
      ];

      await fetch();
      expect(api.lastAccessJwt, 'refreshed');
    });

    test('更新に失敗したら 401 のまま返す', () async {
      api.pages = [(statusCode: 401, users: const <FollowUser>[], cursor: null)];
      api.refreshThrows = true;

      expect((await fetch()).statusCode, 401);
    });

    test('やり直しは 1 回だけ', () async {
      api.pages = [
        (statusCode: 401, users: const <FollowUser>[], cursor: null),
        (statusCode: 401, users: const <FollowUser>[], cursor: null),
      ];

      expect((await fetch()).statusCode, 401);
      expect(api.refreshCount, 1);
    });
  });

  group('中断', () {
    test('開始前に中断されていたら投げる', () async {
      api.page = (statusCode: 200, users: [listed('a')], cursor: null);
      final token = CaptureCancelToken()..cancel();

      expect(() => fetch(cancelToken: token),
          throwsA(isA<CaptureCancelledException>()));
      expect(api.listCalls, 0);
    });

    test('件数の補完中でも抜ける', () async {
      final users = [for (var i = 0; i < 60; i++) listed('u$i')];
      api.page = (statusCode: 200, users: users, cursor: null);
      final token = CaptureCancelToken();
      // 1 バッチ目を引いた時点で中断する
      api.onProfiles = (_) => token.cancel();

      await expectLater(fetch(cancelToken: token),
          throwsA(isA<CaptureCancelledException>()));
      expect(api.profileCalls.length, 1);
    });
  });
}

typedef _Page = ({int statusCode, List<FollowUser> users, String? cursor});

/// BlueskyApiService の差し替え。使うのは 3 メソッドだけなので、
/// 残りは noSuchMethod で落として「触っていない」ことを保証する。
class _FakeBlueskyApi implements BlueskyApiService {
  _Page page = (statusCode: 200, users: const [], cursor: null);

  /// 呼ばれた順に返す。空なら [page] を返し続ける
  List<_Page> pages = [];

  Map<String, FollowUser> profiles = const {};
  Object? profilesThrows;
  bool refreshThrows = false;

  int listCalls = 0;
  int refreshCount = 0;
  bool followersRequested = false;
  String? lastActor;
  String? lastCursor;
  String? lastAccessJwt;
  final List<List<String>> profileCalls = [];
  void Function(List<String> actors)? onProfiles;

  @override
  Future<_Page> getFollowList(
    BlueskyCredentials creds,
    String actor, {
    required bool followers,
    String? cursor,
    int limit = BlueskyApiService.followListPageSize,
  }) async {
    listCalls++;
    followersRequested = followers;
    lastActor = actor;
    lastCursor = cursor;
    lastAccessJwt = creds.accessJwt;
    if (pages.isEmpty) return page;
    return pages.removeAt(0);
  }

  @override
  Future<Map<String, FollowUser>> getProfiles(
    BlueskyCredentials creds,
    List<String> actors,
  ) async {
    profileCalls.add(actors);
    onProfiles?.call(actors);
    final thrown = profilesThrows;
    if (thrown != null) throw thrown;
    return {
      for (final a in actors)
        if (profiles[a] != null) a: profiles[a]!,
    };
  }

  @override
  Future<BlueskyCredentials> refreshSession(BlueskyCredentials creds) async {
    refreshCount++;
    if (refreshThrows) throw BlueskyAuthException('refresh failed');
    return creds.copyWith(accessJwt: 'refreshed', refreshJwt: 'refreshed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} は使わないはず');
}
