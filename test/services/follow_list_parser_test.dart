import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/models/follow_user.dart';
import 'package:mobile_omniverse/services/follow_list_parser.dart';

/// 実レスポンスと同じ入れ物を作る。
/// [timelineKey] / [nested] は X の A/B による形状差を再現するため。
String _envelope(
  List<String> entries, {
  String timelineKey = 'timeline',
  bool nested = true,
}) {
  final instructions =
      '[{"type":"TimelineAddEntries","entries":[${entries.join(',')}]}]';
  final inner = nested
      ? '{"timeline":{"instructions":$instructions}}'
      : '{"instructions":$instructions}';
  return '{"data":{"user":{"result":{"$timelineKey":$inner}}}}';
}

Map<String, dynamic> _decode(String raw) =>
    json.decode(raw) as Map<String, dynamic>;

/// core (新形式) と legacy の両方を持つ通常のユーザー
const _userWithCore = '''
{"entryId":"user-111","content":{"itemContent":{"user_results":{"result":{
  "rest_id":"111",
  "core":{"screen_name":"alice","name":"Alice"},
  "avatar":{"image_url":"https://pbs.twimg.com/alice.jpg"},
  "privacy":{"protected":false},
  "is_blue_verified":true,
  "legacy":{
    "followers_count":1200,"friends_count":300,"statuses_count":42,
    "profile_image_url_https":"https://pbs.twimg.com/alice_legacy.jpg",
    "description":"hello","location":"Tokyo",
    "created_at":"Thu Apr 06 15:24:15 +0000 2023"
  }
}}}}}
''';

/// core が無く legacy だけの旧形式
const _userLegacyOnly = '''
{"entryId":"user-222","content":{"itemContent":{"user_results":{"result":{
  "rest_id":"222",
  "legacy":{
    "screen_name":"bob","name":"Bob",
    "followers_count":10,"friends_count":0,
    "profile_image_url_https":"https://pbs.twimg.com/bob.jpg",
    "protected":true,"verified":false
  }
}}}}}
''';

/// legacy が空で、件数が新しい入れ物にしか無い形。
/// 実機で観測した X の現行レスポンス
const _userNewLayout = '''
{"entryId":"user-333","content":{"itemContent":{"user_results":{"result":{
  "rest_id":"333",
  "core":{"screen_name":"carol","name":"Carol",
          "created_at":"Thu Apr 06 15:24:15 +0000 2023"},
  "avatar":{"image_url":"https://pbs.twimg.com/carol.jpg"},
  "privacy":{"protected":true},
  "verification":{"verified":true},
  "profile_bio":{"description":"new layout"},
  "location":{"location":"Osaka"},
  "relationship_counts":{"followers":88,"following":99},
  "tweet_counts":{"tweets":777,"media_tweets":12},
  "legacy":{}
}}}}}
''';

const _bottomCursor =
    '{"entryId":"cursor-bottom-1","content":{"cursorType":"Bottom","value":"1234|5678"}}';

const _topCursor =
    '{"entryId":"cursor-top-1","content":{"cursorType":"Top","value":"9999|0000"}}';

void main() {
  group('FollowListParser.isTerminalCursor', () {
    test('"0|" 始まりを終端と判定する', () {
      expect(FollowListParser.isTerminalCursor('0|1234567890'), isTrue);
    });

    test('通常のカーソルは終端ではない', () {
      expect(FollowListParser.isTerminalCursor('1234|5678'), isFalse);
    });

    test('null は終端ではない', () {
      expect(FollowListParser.isTerminalCursor(null), isFalse);
    });
  });

  group('FollowListParser.parse', () {
    test('users と bottom cursor を取り出す', () {
      final result =
          FollowListParser.parse(_decode(_envelope([_userWithCore, _bottomCursor])));

      expect(result.users, hasLength(1));
      expect(result.cursor, '1234|5678');

      final alice = result.users.single;
      expect(alice.restId, '111');
      expect(alice.screenName, 'alice');
      expect(alice.name, 'Alice');
      expect(alice.followersCount, 1200);
      expect(alice.friendsCount, 300);
      expect(alice.statusesCount, 42);
      expect(alice.description, 'hello');
      expect(alice.location, 'Tokyo');
      expect(alice.createdAt, 'Thu Apr 06 15:24:15 +0000 2023');
      expect(alice.isProtected, isFalse);
      // legacy.verified が無い場合は is_blue_verified を見る
      expect(alice.verified, isTrue);
      // avatar.image_url が legacy より優先される
      expect(alice.avatarUrl, 'https://pbs.twimg.com/alice.jpg');
    });

    test('legacy が空でも新しい入れ物から件数を読む', () {
      final result =
          FollowListParser.parse(_decode(_envelope([_userNewLayout])));

      final carol = result.users.single;
      expect(carol.screenName, 'carol');
      expect(carol.followersCount, 88);
      expect(carol.friendsCount, 99);
      // legacy.statuses_count しか見ていなかったため投稿数が丸ごと欠けていた
      expect(carol.statusesCount, 777);
      expect(carol.description, 'new layout');
      expect(carol.location, 'Osaka');
      expect(carol.isProtected, isTrue);
      expect(carol.verified, isTrue);
      expect(carol.avatarUrl, 'https://pbs.twimg.com/carol.jpg');
    });

    test('legacy がある相手は legacy を優先する', () {
      final result =
          FollowListParser.parse(_decode(_envelope([_userWithCore])));
      // 両方ある場合に取り違えない
      expect(result.users.single.statusesCount, 42);
    });

    test('どちらにも投稿数が無ければ null', () {
      final result =
          FollowListParser.parse(_decode(_envelope([_userLegacyOnly])));
      expect(result.users.single.statusesCount, isNull);
    });

    test('core が無い旧形式でも legacy から読める', () {
      final result =
          FollowListParser.parse(_decode(_envelope([_userLegacyOnly])));

      final bob = result.users.single;
      expect(bob.screenName, 'bob');
      expect(bob.name, 'Bob');
      expect(bob.avatarUrl, 'https://pbs.twimg.com/bob.jpg');
      // legacy.protected をフォールバックで読む
      expect(bob.isProtected, isTrue);
    });

    test('Top カーソルは次ページ用に採用しない', () {
      final result = FollowListParser.parse(
          _decode(_envelope([_userWithCore, _topCursor])));

      expect(result.cursor, isNull);
    });

    test('timeline_v2 形式でも解析できる', () {
      final result = FollowListParser.parse(_decode(
          _envelope([_userWithCore, _bottomCursor], timelineKey: 'timeline_v2')));

      expect(result.users, hasLength(1));
      expect(result.cursor, '1234|5678');
    });

    test('instructions が直下にある簡略形でも解析できる', () {
      final result = FollowListParser.parse(
          _decode(_envelope([_userWithCore], nested: false)));

      expect(result.users, hasLength(1));
    });

    test('rest_id や screen_name を欠くエントリは捨てる', () {
      const noRestId =
          '{"entryId":"x","content":{"itemContent":{"user_results":{"result":{"core":{"screen_name":"ghost"}}}}}}';
      const noScreenName =
          '{"entryId":"y","content":{"itemContent":{"user_results":{"result":{"rest_id":"333"}}}}}';

      final result = FollowListParser.parse(
          _decode(_envelope([noRestId, noScreenName, _userWithCore])));

      expect(result.users.map((u) => u.restId), ['111']);
    });

    test('user_results を持たないエントリは無視する', () {
      const banner =
          '{"entryId":"banner","content":{"itemContent":{"itemType":"TimelineMessagePrompt"}}}';

      final result =
          FollowListParser.parse(_decode(_envelope([banner, _userWithCore])));

      expect(result.users, hasLength(1));
    });

    test('想定外の形状でも例外を投げず空を返す', () {
      expect(FollowListParser.parse(_decode('{}')).users, isEmpty);
      expect(FollowListParser.parse(_decode('{"data":{}}')).cursor, isNull);
      expect(
        FollowListParser.parse(_decode('{"data":{"user":{"result":[]}}}')).users,
        isEmpty,
      );
    });
  });

  group('FollowUser', () {
    test('followRatio はフォロー数が 0 なら null', () {
      const zero = FollowUser(
          restId: '1', screenName: 'a', name: 'A', followersCount: 10);
      expect(zero.followRatio, isNull);
    });

    test('followRatio はフォロワー数 / フォロー数', () {
      const u = FollowUser(
        restId: '1',
        screenName: 'a',
        name: 'A',
        followersCount: 300,
        friendsCount: 150,
      );
      expect(u.followRatio, 2.0);
    });

    test('toJson / fromJson が往復する', () {
      final original =
          FollowListParser.parse(_decode(_envelope([_userWithCore]))).users.single;
      final restored = FollowUser.fromJson(original.toJson());

      expect(restored.restId, original.restId);
      expect(restored.screenName, original.screenName);
      expect(restored.followersCount, original.followersCount);
      expect(restored.statusesCount, original.statusesCount);
      expect(restored.verified, original.verified);
      expect(restored.isProtected, original.isProtected);
      expect(restored.createdAt, original.createdAt);
    });
  });
}
