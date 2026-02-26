import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

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
      .thenAnswer((_) async => http.Response(body, statusCode, headers: headers));

  when(() => client.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
        encoding: any(named: 'encoding'),
      )).thenAnswer(
          (_) async => http.Response(body, statusCode, headers: headers));

  return client;
}
