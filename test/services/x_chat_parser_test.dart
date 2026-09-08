import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/x_chat_parser.dart';

/// XChat のメッセージイベント（Thrift Binary）を組み立てる
class _Event {
  final _b = BytesBuilder();

  void str(int fid, String v) => raw(fid, utf8.encode(v));

  void raw(int fid, List<int> bytes) {
    _b.addByte(11);
    _i16(fid);
    _i32(bytes.length);
    _b.add(bytes);
  }

  void structStart(int fid) {
    _b.addByte(12);
    _i16(fid);
  }

  void stop() => _b.addByte(0);

  void _i16(int v) => _b.add((ByteData(2)..setInt16(0, v)).buffer.asUint8List());
  void _i32(int v) => _b.add((ByteData(4)..setInt32(0, v)).buffer.asUint8List());

  Uint8List get bytes => _b.toBytes();
  String get b64 => base64.encode(_b.toBytes());
}

/// テキストのメッセージ 1 件
String textEvent({
  required String id,
  required String senderId,
  required String sentAtMillis,
  required String text,
}) {
  // 本文は入れ子の Thrift の 1 → 1 → 1
  final body = _Event()
    ..structStart(1)
    ..structStart(1)
    ..str(1, text)
    ..stop()
    ..stop()
    ..stop();
  final e = _Event()
    ..str(1, id)
    ..str(3, senderId)
    ..str(4, '742212954:2001557530871468032')
    ..str(6, sentAtMillis)
    ..structStart(7)
    ..structStart(1)
    ..raw(100, body.bytes)
    ..stop()
    ..stop()
    ..stop();
  return e.b64;
}

/// 添付（入れ子の Thrift が本文の位置に入る）
String mediaEvent({required String id, required String senderId}) {
  final body = _Event()
    ..str(6, 'i9ica_Q9.jpg')
    ..str(8, 'https://ton.x.com/i/ton/data/dm/1/2/i9ica_Q9.jpg')
    ..stop();
  final e = _Event()
    ..str(1, id)
    ..str(3, senderId)
    ..str(6, '1787041992489')
    ..structStart(7)
    ..structStart(1)
    ..raw(100, body.bytes)
    ..stop()
    ..stop()
    ..stop();
  return e.b64;
}

void main() {
  group('メッセージ 1 件', () {
    test('本文・送信者・時刻を取り出す', () {
      final m = XChatParser.parseEvent(
        textEvent(
          id: '1007833643987812356',
          senderId: '742212954',
          sentAtMillis: '1787041992489',
          text: 'はじめまして',
        ),
        selfUserId: '742212954',
      );
      expect(m, isNotNull);
      expect(m!.id, '1007833643987812356');
      expect(m.senderId, '742212954');
      expect(m.text, 'はじめまして');
      expect(m.sentAt, DateTime.fromMillisecondsSinceEpoch(1787041992489));
      expect(m.isMine, isTrue);
    });

    test('自分以外の送信は isMine が false', () {
      final m = XChatParser.parseEvent(
        textEvent(
          id: '1',
          senderId: '2001557530871468032',
          sentAtMillis: '1787041992489',
          text: 'やあ',
        ),
        selfUserId: '742212954',
      );
      expect(m!.isMine, isFalse);
    });

    // 画像のときは本文の位置に入れ子の Thrift が入る
    test('添付は URL を取り出す', () {
      final m = XChatParser.parseEvent(
        mediaEvent(id: '9', senderId: '742212954'),
        selfUserId: '742212954',
      );
      expect(m, isNotNull);
      expect(m!.text, isEmpty);
      expect(m.mediaUrl, startsWith('https://ton.x.com/'));
      expect(m.attachmentLabel, '画像');
    });

    // 既読や参加のイベントには本文が無い
    test('本文も添付も無いイベントは捨てる', () {
      final e = _Event()
        ..str(1, '1')
        ..str(3, '2')
        ..str(6, '1787041992489')
        ..stop();
      expect(XChatParser.parseEvent(e.b64), isNull);
    });

    test('壊れた入力でも落ちない', () {
      expect(XChatParser.parseEvent('!!!notbase64'), isNull);
    });
  });

  group('スレッド', () {
    test('新しい順に並べる', () {
      final data = {
        'get_conversation_page': {
          'encoded_message_events': [
            textEvent(
                id: '1',
                senderId: '742212954',
                sentAtMillis: '1000',
                text: '古い'),
            textEvent(
                id: '2',
                senderId: '742212954',
                sentAtMillis: '3000',
                text: '新しい'),
            textEvent(
                id: '3',
                senderId: '742212954',
                sentAtMillis: '2000',
                text: '中間'),
          ],
        }
      };
      final list = XChatParser.parseConversation(data);
      expect(list.map((m) => m.text).toList(), ['新しい', '中間', '古い']);
    });

    test('応答が空でも落ちない', () {
      expect(XChatParser.parseConversation(const {}), isEmpty);
      expect(
          XChatParser.parseConversation(
              const {'get_conversation_page': {}}),
          isEmpty);
    });
  });

  group('会話一覧', () {
    Map<String, dynamic> inbox() => {
          'get_initial_chat_page': {
            'items': [
              {
                'conversation_detail': {
                  'conversation_id': '1007833643987812356',
                  'is_muted': false,
                  'participants_results': [
                    {
                      'rest_id': '2001557530871468032',
                      'result': {
                        'core': {'name': 'アリス', 'screen_name': 'alice'},
                        'avatar': {'image_url': 'https://img/alice.jpg'},
                      },
                    },
                    // 自分は相手一覧から外す
                    {'rest_id': '742212954', 'result': const {}},
                  ],
                },
                'latest_message_events': [
                  textEvent(
                      id: '1',
                      senderId: '2001557530871468032',
                      sentAtMillis: '2000',
                      text: '最新のことば'),
                  textEvent(
                      id: '2',
                      senderId: '2001557530871468032',
                      sentAtMillis: '1000',
                      text: '古いことば'),
                ],
              },
            ],
          }
        };

    test('相手・最新メッセージ・時刻がそろう', () {
      final convos = XChatParser.parseInbox(inbox(), selfUserId: '742212954');
      expect(convos, hasLength(1));
      final c = convos.first;
      expect(c.id, '1007833643987812356');
      expect(c.title, 'アリス');
      expect(c.members.map((m) => m.id), ['2001557530871468032']);
      expect(c.members.first.handle, 'alice');
      // 一覧に出るのは最新の 1 件
      expect(c.lastText, '最新のことば');
      expect(c.lastAt, DateTime.fromMillisecondsSinceEpoch(2000));
      expect(c.isGroup, isFalse);
    });

    test('応答が空でも落ちない', () {
      expect(XChatParser.parseInbox(const {}), isEmpty);
    });
  });
}
