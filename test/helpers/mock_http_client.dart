import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

/// http.Response(String, ...) は latin1 で符号化するので、日本語を含む
/// 応答を組み立てられない。実際の X / Bluesky は UTF-8 で返すので、
/// バイト列から組んで合わせる。
http.Response _utf8Response(String body, int statusCode,
        {Map<String, String> headers = const {}}) =>
    http.Response.bytes(utf8.encode(body), statusCode, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers,
    });

class MockHttpClient extends Mock implements http.Client {}

class FakeUri extends Fake implements Uri {}

/// テスト前に registerFallbackValue しておく
void registerHttpFallbacks() {
  registerFallbackValue(FakeUri());
}

/// 固定レスポンスを返す MockHttpClient を作成
MockHttpClient createMockClient({
  int statusCode = 200,
  String body = '{}',
  Map<String, String> headers = const {},
}) {
  final client = MockHttpClient();

  when(() => client.get(any(), headers: any(named: 'headers')))
      .thenAnswer((_) async => _utf8Response(body, statusCode, headers: headers));

  when(() => client.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
        encoding: any(named: 'encoding'),
      )).thenAnswer(
          (_) async => _utf8Response(body, statusCode, headers: headers));

  return client;
}

/// URL ごとに応答を変えたいときのモック。
/// [respond] は (statusCode, body) を返す
MockHttpClient createUriAwareClient(
  (int, String) Function(Uri uri) respond, {
  Map<String, String> headers = const {'content-type': 'application/json'},
}) {
  final client = MockHttpClient();

  Future<http.Response> handle(Invocation invocation) async {
    final uri = invocation.positionalArguments.first as Uri;
    final (status, body) = respond(uri);
    return _utf8Response(body, status, headers: headers);
  }

  when(() => client.get(any(), headers: any(named: 'headers')))
      .thenAnswer(handle);
  when(() => client.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
        encoding: any(named: 'encoding'),
      )).thenAnswer(handle);

  return client;
}
