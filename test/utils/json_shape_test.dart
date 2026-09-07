import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/utils/json_shape.dart';

void main() {
  group('形だけを取り出す', () {
    test('キー名は残す', () {
      final s = jsonShape({'text': 'a', 'sender_id': 1});
      expect(s, contains('text'));
      expect(s, contains('sender_id'));
    });

    test('文字列は長さだけにする', () {
      expect(jsonShape({'text': 'hello'}), '{text: str(5)}');
    });

    test('配列は件数と先頭の形だけ', () {
      final s = jsonShape({
        'entries': [
          {'id': 1},
          {'id': 2},
          {'id': 3},
        ]
      });
      expect(s, '{entries: [3件 {id: int(1桁)}]}');
    });

    test('空配列', () {
      expect(jsonShape({'entries': []}), '{entries: []}');
    });

    test('深すぎるところは畳む', () {
      final deep = {
        'a': {
          'b': {'c': 'x'}
        }
      };
      expect(jsonShape(deep, maxDepth: 1), '{a: {b: …}}');
    });
  });

  // ここが崩れると DM の本文がログに残る。必ず守る
  group('本文を漏らさない', () {
    test('文字列の中身は出さない', () {
      const secret = 'いきなりDM失礼します';
      final s = jsonShape({'text': secret});
      expect(s.contains(secret), isFalse);
      expect(s.contains('DM'), isFalse);
    });

    test('入れ子の奥にある文字列も出さない', () {
      final s = jsonShape({
        'messages': [
          {
            'message_data': {'text': 'ひみつの本文', 'sender_id': '12345'}
          }
        ]
      });
      expect(s.contains('ひみつ'), isFalse);
      expect(s.contains('12345'), isFalse);
      // キー名と形は残る
      expect(s, contains('message_data'));
      expect(s, contains('text: str(6)'));
    });

    test('数値そのものは出さない（id を残さない）', () {
      final s = jsonShape({'id': 2089631687315730578});
      expect(s.contains('2089631687315730578'), isFalse);
      expect(s, contains('19桁'));
    });
  });
}
