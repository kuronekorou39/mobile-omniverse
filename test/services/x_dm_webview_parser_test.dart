import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/x_dm_webview_parser.dart';

void main() {
  group('スレッド', () {
    // DOM は画面と同じ古い順。表示は新しい順で使うので入れ替える
    test('新しい順に直す', () {
      final list = XDmWebViewParser.parseConversation([
        {'id': 'a', 'text': '古い', 'mine': false},
        {'id': 'b', 'text': '中間', 'mine': true},
        {'id': 'c', 'text': '新しい', 'mine': false},
      ]);
      expect(list.map((m) => m.text).toList(), ['新しい', '中間', '古い']);
    });

    // DOM からは送信者 ID が取れない。吹き出しの寄りだけが手がかり
    test('右寄りを自分の発言として扱う', () {
      final list = XDmWebViewParser.parseConversation([
        {'id': 'a', 'text': 'こちら', 'mine': true},
        {'id': 'b', 'text': 'あちら', 'mine': false},
      ], selfUserId: '742212954');
      final mine = list.firstWhere((m) => m.text == 'こちら');
      final theirs = list.firstWhere((m) => m.text == 'あちら');
      expect(mine.isMine, isTrue);
      expect(mine.senderId, '742212954');
      expect(theirs.isMine, isFalse);
    });

    test('空の吹き出しは捨てる', () {
      final list = XDmWebViewParser.parseConversation([
        {'id': 'a', 'text': '  ', 'mine': false},
        {'id': 'b', 'text': 'ある', 'mine': false},
      ]);
      expect(list, hasLength(1));
    });

    test('id が無くても落ちない', () {
      final list = XDmWebViewParser.parseConversation([
        {'text': 'やあ', 'mine': false},
      ]);
      expect(list.single.id, isNotEmpty);
    });
  });

  group('会話一覧', () {
    test('相手の ID を会話 ID から取り出す', () {
      final convos = XDmWebViewParser.parseInbox([
        {
          'id': '270931591:742212954',
          'title': 'おーろく',
          'time': '1w',
          'last': 'シルバーウィークのど真ん中に朝5時出…',
        },
      ]);
      expect(convos, hasLength(1));
      final c = convos.single;
      expect(c.id, '270931591:742212954');
      expect(c.title, 'おーろく');
      expect(c.lastText, startsWith('シルバーウィーク'));
      expect(c.members.single.id, '742212954');
    });

    // 一覧の時刻は "1w" のような相対表記で、日時には直せない
    test('時刻は持たない', () {
      final convos = XDmWebViewParser.parseInbox([
        {'id': 'a:b', 'title': 'x', 'time': '1w', 'last': 'y'},
      ]);
      expect(convos.single.lastAt, isNull);
    });

    test('id が無い行は捨てる', () {
      expect(XDmWebViewParser.parseInbox([
        {'title': 'x', 'last': 'y'},
      ]), isEmpty);
    });
  });
}
