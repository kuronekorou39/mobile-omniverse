import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/services/follow_list_parser.dart';

/// X が一覧ページを開いたときに投げる UserByScreenName の URL
String _url(String screenName) {
  final vars = Uri.encodeComponent(
      '{"screen_name":"$screenName","withGrokTranslatedBio":false}');
  return 'https://x.com/i/api/graphql/abc/UserByScreenName'
      '?variables=$vars&features=%7B%7D';
}

String _user({
  required String screenName,
  bool protected = false,
  bool following = false,
  bool newShape = false,
}) {
  if (newShape) {
    // legacy を空にして core / privacy / relationship_perspectives へ移した形
    return '{"data":{"user":{"result":{"__typename":"User","rest_id":"1",'
        '"core":{"screen_name":"$screenName","name":"N"},'
        '"privacy":{"protected":$protected},'
        '"relationship_perspectives":{"following":$following},'
        '"legacy":{}}}}}';
  }
  return '{"data":{"user":{"result":{"__typename":"User","rest_id":"1",'
      '"legacy":{"screen_name":"$screenName","name":"N",'
      '"protected":$protected,"following":$following}}}}}';
}

const _suspended = '{"data":{"user":{"result":{"__typename":"UserUnavailable",'
    '"reason":"Suspended","message":"Account suspended"}}}}';
const _missing = '{"data":{}}';
const _missingUser = '{"data":{"user":{}}}';

void main() {
  group('FollowTargetState.parse', () {
    test('公開アカウントは読める', () {
      final s =
          FollowTargetState.parse(_url('alice'), _user(screenName: 'alice'));
      expect(s?.screenName, 'alice');
      expect(s?.availability, FollowTargetAvailability.available);
      expect(s?.readable, isTrue);
    });

    test('鍵でフォローしていなければ非公開', () {
      final s = FollowTargetState.parse(
          _url('Alice'), _user(screenName: 'Alice', protected: true));
      // 比較しやすいように @ID は小文字にそろえる
      expect(s?.screenName, 'alice');
      expect(s?.availability, FollowTargetAvailability.protected);
      expect(s?.availability.label, '非公開');
    });

    test('鍵でもフォローしていれば読める', () {
      final s = FollowTargetState.parse(_url('alice'),
          _user(screenName: 'alice', protected: true, following: true));
      expect(s?.availability, FollowTargetAvailability.available);
    });

    test('legacy が空の新しい形でも privacy / relationship_perspectives から読む',
        () {
      final locked = FollowTargetState.parse(_url('alice'),
          _user(screenName: 'alice', protected: true, newShape: true));
      expect(locked?.availability, FollowTargetAvailability.protected);

      final followed = FollowTargetState.parse(
          _url('alice'),
          _user(
              screenName: 'alice',
              protected: true,
              following: true,
              newShape: true));
      expect(followed?.availability, FollowTargetAvailability.available);
    });

    test('凍結は suspended', () {
      final s = FollowTargetState.parse(_url('bob'), _suspended);
      expect(s?.availability, FollowTargetAvailability.suspended);
      expect(s?.message, 'Account suspended');
      expect(s?.availability.label, '凍結');
    });

    test('凍結以外の UserUnavailable は unavailable', () {
      const body = '{"data":{"user":{"result":{"__typename":"UserUnavailable",'
          '"reason":"Something","message":"x"}}}}';
      final s = FollowTargetState.parse(_url('bob'), body);
      expect(s?.availability, FollowTargetAvailability.unavailable);
    });

    test('data が空なら存在しない。@ID は URL から取る', () {
      for (final body in [_missing, _missingUser]) {
        final s = FollowTargetState.parse(_url('gone'), body);
        expect(s?.screenName, 'gone');
        expect(s?.availability, FollowTargetAvailability.missing);
      }
    });

    test('URL に screen_name が無く本文も空なら判断しない', () {
      expect(
          FollowTargetState.parse(
              'https://x.com/i/api/graphql/abc/UserByScreenName', _missing),
          isNull);
    });

    test('URL に screen_name が無くても本文から @ID を読む', () {
      final s = FollowTargetState.parse(
          'https://x.com/i/api/graphql/abc/UserByScreenName',
          _user(screenName: 'Carol', protected: true));
      expect(s?.screenName, 'carol');
      expect(s?.availability, FollowTargetAvailability.protected);
    });

    test('UserByScreenName の形でない応答は null', () {
      expect(FollowTargetState.parse(_url('alice'), 'not json'), isNull);
      expect(FollowTargetState.parse(_url('alice'), '{"errors":[]}'), isNull);
      expect(FollowTargetState.parse(_url('alice'), '[]'), isNull);
    });
  });
}
