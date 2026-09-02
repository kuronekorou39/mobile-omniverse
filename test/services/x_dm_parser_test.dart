import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/x_dm_parser.dart';

void main() {
  // 実際の inbox_initial_state.json / conversation.json の形を模した最小構成。
  // entries + users + conversations の同じ部品でできている
  Map<String, dynamic> user(String id, String screen, String name) => {
        'id_str': id,
        'name': name,
        'screen_name': screen,
        'profile_image_url_https': 'https://img/$screen.jpg',
      };

  Map<String, dynamic> messageEntry({
    required String msgId,
    required String convoId,
    required String senderId,
    required String text,
    required int timeMs,
    Map<String, dynamic>? entities,
    Map<String, dynamic>? attachment,
  }) =>
      {
        'message': {
          'id': msgId,
          'time': '$timeMs',
          'conversation_id': convoId,
          'message_data': {
            'id': msgId,
            'time': '$timeMs',
            'sender_id': senderId,
            'text': text,
            if (entities != null) 'entities': entities,
            if (attachment != null) 'attachment': attachment,
          },
        },
      };

  group('parseInbox', () {
    Map<String, dynamic> inboxPayload() => {
          'entries': [
            messageEntry(
                msgId: '900',
                convoId: '11-22',
                senderId: '22',
                text: 'こんにちは',
                timeMs: 2000),
            messageEntry(
                msgId: '800',
                convoId: 'g-1',
                senderId: '33',
                text: 'グループの発言',
                timeMs: 1000),
          ],
          'users': {
            '11': user('11', 'me', '自分'),
            '22': user('22', 'alice', 'アリス'),
            '33': user('33', 'bob', 'ボブ'),
          },
          'conversations': {
            '11-22': {
              'conversation_id': '11-22',
              'type': 'ONE_TO_ONE',
              'sort_event_id': '900',
              'sort_timestamp': '2000',
              'trusted': true,
              'muted': false,
              'participants': [
                {'user_id': '11', 'last_read_event_id': '500'},
                {'user_id': '22', 'last_read_event_id': '900'},
              ],
            },
            'g-1': {
              'conversation_id': 'g-1',
              'type': 'GROUP_DM',
              'name': '作戦会議',
              'sort_event_id': '800',
              'sort_timestamp': '1000',
              'trusted': false,
              'participants': [
                {'user_id': '11', 'last_read_event_id': '800'},
                {'user_id': '22'},
                {'user_id': '33'},
              ],
            },
          },
          'inbox_timelines': {
            'trusted': {'status': 'HAS_MORE', 'min_entry_id': '700'},
            'untrusted': {'status': 'AT_END', 'min_entry_id': '600'},
          },
        };

    test('会話一覧・自分の解決・未読・カーソルがそろう', () {
      final page = XDmParser.parseInbox(inboxPayload(), selfHandle: '@Me');

      expect(page.selfUserId, '11'); // ハンドルから users を引いて解決
      expect(page.conversations, hasLength(2));

      // 新しい順
      final oneToOne = page.conversations[0];
      expect(oneToOne.id, '11-22');
      expect(oneToOne.title, 'アリス');
      expect(oneToOne.isGroup, isFalse);
      expect(oneToOne.lastText, 'こんにちは');
      // 自分の last_read (500) < sort_event_id (900) なので未読
      expect(oneToOne.hasUnread, isTrue);
      expect(oneToOne.isRequest, isFalse);
      // 相手は自分を含まない
      expect(oneToOne.members.map((m) => m.id), ['22']);

      final group = page.conversations[1];
      expect(group.title, '作戦会議'); // グループ名があればそれを使う
      expect(group.isGroup, isTrue);
      expect(group.hasUnread, isFalse); // 読み切っている
      expect(group.isRequest, isTrue); // trusted: false はリクエスト
      expect(group.members, hasLength(2));

      // カーソルは AT_END なら終端扱い
      expect(page.trustedNextMaxId, '700');
      expect(page.untrustedNextMaxId, isNull);
    });

    test('続きページはトップレベルのカーソルを読む', () {
      final payload = inboxPayload()
        ..remove('inbox_timelines')
        ..['status'] = 'HAS_MORE'
        ..['min_entry_id'] = '550';
      final page = XDmParser.parseInbox(payload, selfUserId: '11');
      expect(page.nextMaxId, '550');

      payload['status'] = 'AT_END';
      expect(XDmParser.parseInbox(payload, selfUserId: '11').nextMaxId,
          isNull);
    });
  });

  test('entryTypeHistogram は entry の種類を数える', () {
    final hist = XDmParser.entryTypeHistogram({
      'entries': [
        messageEntry(
            msgId: '1', convoId: 'c', senderId: '2', text: 'a', timeMs: 1),
        messageEntry(
            msgId: '2', convoId: 'c', senderId: '2', text: 'b', timeMs: 2),
        {'reaction_create': {}},
      ],
    });
    expect(hist, {'message': 2, 'reaction_create': 1});
  });

  group('parseThread', () {
    test('新しい順に並び、自分の発言と添付が分かる', () {
      final payload = {
        'status': 'HAS_MORE',
        'min_entry_id': '100',
        'entries': [
          messageEntry(
            msgId: '300',
            convoId: '11-22',
            senderId: '11',
            text: '写真送るね https://t.co/abc',
            timeMs: 3000,
            attachment: {
              'photo': {
                'url': 'https://t.co/abc',
                'media_url_https': 'https://ton.x.com/dm/photo.jpg',
              },
            },
          ),
          messageEntry(
            msgId: '100',
            convoId: '11-22',
            senderId: '22',
            text: 'これ見て https://t.co/xyz',
            timeMs: 1000,
            entities: {
              'urls': [
                {
                  'url': 'https://t.co/xyz',
                  'expanded_url': 'https://example.com/page',
                },
              ],
            },
          ),
          // message 以外のイベントは無視する
          {
            'reaction_create': {'id': '999'},
          },
        ],
        'users': {
          '11': user('11', 'me', '自分'),
          '22': user('22', 'alice', 'アリス'),
        },
        'conversations': {'11-22': {}},
      };

      final page = XDmParser.parseThread(payload, selfUserId: '11');
      expect(page.messages, hasLength(2));
      expect(page.nextMaxId, '100');

      final mine = page.messages[0];
      expect(mine.isMine, isTrue);
      // 添付の t.co は本文から消え、メディアとして別枠になる
      expect(mine.text, '写真送るね');
      expect(mine.mediaUrl, 'https://ton.x.com/dm/photo.jpg');
      expect(mine.attachmentLabel, '画像');

      final theirs = page.messages[1];
      expect(theirs.isMine, isFalse);
      expect(theirs.senderName, 'アリス');
      // 短縮 URL は entities で展開される
      expect(theirs.text, 'これ見て https://example.com/page');
      expect(theirs.sentAt,
          DateTime.fromMillisecondsSinceEpoch(1000));
    });

    test('ポスト参照は中身（本文・作者・URL）ごと取り出す', () {
      final payload = {
        'entries': [
          messageEntry(
            msgId: '500',
            convoId: '11-22',
            senderId: '22',
            text: '見て https://t.co/tw',
            timeMs: 5000,
            attachment: {
              'tweet': {
                'url': 'https://t.co/tw',
                'expanded_url': 'https://x.com/bob/status/123',
                'status': {
                  'full_text': '面白い出来事があった',
                  'user': {'name': 'ボブ', 'screen_name': 'bob'},
                },
              },
            },
          ),
        ],
        'users': {'22': user('22', 'alice', 'アリス')},
      };

      final m = XDmParser.parseThread(payload, selfUserId: '11').messages.single;
      // 参照の t.co は本文から消え、カードとして別枠になる
      expect(m.text, '見て');
      expect(m.attachmentLabel, 'ポスト');
      expect(m.quoteText, '面白い出来事があった');
      expect(m.quoteAuthor, 'ボブ');
      expect(m.quoteHandle, 'bob');
      expect(m.quoteUrl, 'https://x.com/bob/status/123');
    });

    test('AT_END ならそれより前は読まない', () {
      final page = XDmParser.parseThread({
        'status': 'AT_END',
        'min_entry_id': '100',
        'entries': [],
      });
      expect(page.nextMaxId, isNull);
    });
  });
}
