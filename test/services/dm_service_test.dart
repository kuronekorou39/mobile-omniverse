import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/services/bluesky_api_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_http_client.dart';

/// DM（見る専）のサービス層。Bluesky のみ。
///
/// この機能の柱は「読み取り専用＝既読をつける API を呼ばない」なので、
/// パースだけでなく **一切 POST しない** ことも検証する。
///
/// X は対象外。DM が XChat に移り、本文が端末の鍵で暗号化された。
void main() {
  setUp(() {
    registerHttpFallbacks();
    SharedPreferences.setMockInitialValues({});
  });


  group('BlueskyApiService DM', () {
    final service = BlueskyApiService.instance;
    const creds = BlueskyCredentials(
      accessJwt: 'jwt',
      refreshJwt: 'r',
      did: 'did:plc:me',
      handle: 'me.bsky.social',
    );

    tearDown(() {
      service.httpClientOverride = null;
    });

    test('listConvos は chat プロキシ宛てで、自分は members から除く', () async {
      final client = createUriAwareClient((_) => (200, jsonEncode({
                'cursor': 'next',
                'convos': [
                  {
                    'id': 'convo1',
                    'unreadCount': 3,
                    'muted': false,
                    'members': [
                      {'did': 'did:plc:me', 'handle': 'me.bsky.social'},
                      {
                        'did': 'did:plc:alice',
                        'handle': 'alice.bsky.social',
                        'displayName': 'アリス',
                        'avatar': 'https://cdn/alice.jpg',
                      },
                    ],
                    'lastMessage': {
                      r'$type': 'chat.bsky.convo.defs#messageView',
                      'text': 'やあ',
                      'sentAt': '2026-09-01T10:00:00.000Z',
                    },
                  },
                ],
              })));
      service.httpClientOverride = client;

      final res = await service.listConvos(creds);
      expect(res.cursor, 'next');
      expect(res.convos, hasLength(1));
      final c = res.convos.first;
      expect(c.id, 'convo1');
      expect(c.title, 'アリス');
      expect(c.members.map((m) => m.id), ['did:plc:alice']);
      expect(c.hasUnread, isTrue);
      expect(c.unreadCount, 3);
      expect(c.lastText, 'やあ');

      // chat 系はプロキシヘッダ必須。無いと PDS が chat を解決できない
      final captured = verify(() =>
              client.get(captureAny(), headers: captureAny(named: 'headers')))
          .captured;
      final headers = captured[1] as Map<String, String>;
      expect(headers['atproto-proxy'], 'did:web:api.bsky.chat#bsky_chat');
      final uri = captured[0] as Uri;
      expect(uri.path, '/xrpc/chat.bsky.convo.listConvos');

      verifyNever(() => client.post(any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
          encoding: any(named: 'encoding')));
    });

    test('getMessages は自分の発言と削除済みを判別する', () async {
      service.httpClientOverride = createMockClient(
          body: jsonEncode({
        'messages': [
          {
            r'$type': 'chat.bsky.convo.defs#messageView',
            'id': 'm2',
            'text': '返事',
            'sender': {'did': 'did:plc:me'},
            'sentAt': '2026-09-01T10:05:00.000Z',
          },
          {
            r'$type': 'chat.bsky.convo.defs#deletedMessageView',
            'id': 'm1',
            'sender': {'did': 'did:plc:alice'},
            'sentAt': '2026-09-01T10:00:00.000Z',
          },
        ],
      }));

      final res = await service.getConvoMessages(creds, 'convo1');
      expect(res.messages, hasLength(2));
      expect(res.messages[0].isMine, isTrue);
      expect(res.messages[0].text, '返事');
      expect(res.messages[1].isMine, isFalse);
      expect(res.messages[1].text, '（削除されたメッセージ）');
    });

    test('期限切れトークンは BlueskyAuthException になる', () async {
      service.httpClientOverride = createMockClient(
          statusCode: 400,
          body: jsonEncode({'error': 'ExpiredToken', 'message': 'expired'}));
      expect(() => service.listConvos(creds),
          throwsA(isA<BlueskyAuthException>()));
    });

    // DM が使えないセッションの断り方は実測で 3 通りあった。どれも
    // リフレッシュでは直らないので、期限切れ扱いにしてはいけない
    test('Bad token scope はアプリパスワードの案内を出す', () async {
      service.httpClientOverride = createMockClient(
          statusCode: 400,
          body: jsonEncode(
              {'error': 'InvalidToken', 'message': 'Bad token scope'}));
      expect(
          () => service.listConvos(creds),
          throwsA(isA<BlueskyApiException>().having(
              (e) => '$e', 'message', contains('アプリパスワード'))));
    });

    test('Bad token method もアプリパスワードの案内を出す', () async {
      service.httpClientOverride = createMockClient(
          statusCode: 400,
          body: jsonEncode(
              {'error': 'InvalidToken', 'message': 'Bad token method'}));
      expect(
          () => service.listConvos(creds),
          throwsA(isA<BlueskyApiException>().having(
              (e) => '$e', 'message', contains('アプリパスワード'))));
    });

    test('501 もアプリパスワードの案内を出す', () async {
      service.httpClientOverride = createMockClient(
          statusCode: 501,
          body: jsonEncode({
            'error': 'MethodNotImplemented',
            'message': 'Method Not Implemented'
          }));
      expect(
          () => service.listConvos(creds),
          throwsA(isA<BlueskyApiException>().having(
              (e) => '$e', 'message', contains('アプリパスワード'))));
    });

    test('その他のエラーは本文を画面まで届ける（原因調査用）', () async {
      service.httpClientOverride = createMockClient(
          statusCode: 400,
          body: jsonEncode(
              {'error': 'InvalidRequest', 'message': 'bad params'}));
      expect(
          () => service.listConvos(creds),
          throwsA(isA<BlueskyApiException>().having((e) => '$e', 'message',
              allOf(contains('InvalidRequest'), contains('bad params')))));
    });
  });
}
