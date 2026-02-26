import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/models/account.dart';
import 'package:mobile_omniverse/services/x_query_id_service.dart';

import '../helpers/mock_http_client.dart';

void main() {
  late XQueryIdService service;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    service = XQueryIdService.instance;
  });

  group('XQueryIdService', () {
    test('getQueryId returns default for known operation when no cache', () async {
      await service.clearCache();

      final queryId = service.getQueryId('HomeLatestTimeline');
      expect(queryId, 'BKB7oi212Fi7kQtCBGE4zA');
    });

    test('getQueryId returns default for TweetDetail', () async {
      await service.clearCache();

      final queryId = service.getQueryId('TweetDetail');
      expect(queryId, 'nBS-WpgA6ZG0CyNHD517JQ');
    });

    test('getQueryId returns empty string for unknown operation', () async {
      await service.clearCache();

      final queryId = service.getQueryId('NonExistentOperation');
      expect(queryId, '');
    });

    test('init loads cached queryIds from SharedPreferences', () async {
      // Pre-populate SharedPreferences with cached data
      final cached = {
        'HomeLatestTimeline': 'cachedId123',
        'TweetDetail': 'cachedId456',
      };
      SharedPreferences.setMockInitialValues({
        'x_query_ids': json.encode(cached),
      });

      await service.init();

      expect(service.getQueryId('HomeLatestTimeline'), 'cachedId123');
      expect(service.getQueryId('TweetDetail'), 'cachedId456');
    });

    test('clearCache resets to defaults', () async {
      // First, simulate cached data
      final cached = {
        'HomeLatestTimeline': 'overriddenId',
      };
      SharedPreferences.setMockInitialValues({
        'x_query_ids': json.encode(cached),
      });
      await service.init();
      expect(service.getQueryId('HomeLatestTimeline'), 'overriddenId');

      // Clear cache
      await service.clearCache();

      // Should now return default
      expect(service.getQueryId('HomeLatestTimeline'), 'BKB7oi212Fi7kQtCBGE4zA');
    });

    test('currentIds returns all operations with their queryIds', () async {
      await service.clearCache();

      final ids = service.currentIds;

      expect(ids, containsPair('HomeLatestTimeline', 'BKB7oi212Fi7kQtCBGE4zA'));
      expect(ids, containsPair('TweetDetail', 'nBS-WpgA6ZG0CyNHD517JQ'));
      expect(ids, containsPair('FavoriteTweet', 'lI07N6Otwv1PhnEgXILM7A'));
      expect(ids, containsPair('UnfavoriteTweet', 'ZYKSe-w7KEslx3JhSIk5LA'));
      expect(ids, containsPair('CreateRetweet', 'ojPdsZsimiJrUGLR1sjUtA'));
      expect(ids, containsPair('DeleteRetweet', 'iQtK4dl5hBmXewYZuEOKVw'));
      expect(ids, containsPair('CreateTweet', 'a1p9RWpkYKBjWv_I3WzS-A'));
      expect(ids, containsPair('UserByRestId', 'tD8zKvQzwY3kdx5yz6YmOw'));
      expect(ids.length, 8);
    });

    test('currentIds is unmodifiable', () async {
      await service.clearCache();

      final ids = service.currentIds;
      expect(
        () => ids['HomeLatestTimeline'] = 'tampered',
        throwsUnsupportedError,
      );
    });

    test('clearCache removes prefs keys', () async {
      SharedPreferences.setMockInitialValues({
        'x_query_ids': json.encode({'HomeLatestTimeline': 'old'}),
        'x_query_ids_last_refresh': 1000000,
      });
      await service.init();

      await service.clearCache();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('x_query_ids'), isNull);
      expect(prefs.getInt('x_query_ids_last_refresh'), isNull);
    });

    test('lastRefreshTime is null after clearCache', () async {
      await service.clearCache();
      expect(service.lastRefreshTime, isNull);
    });

    test('init with corrupted JSON does not crash', () async {
      SharedPreferences.setMockInitialValues({
        'x_query_ids': 'not valid json',
      });

      // Should not throw
      await service.init();

      // Falls back to defaults
      expect(service.getQueryId('HomeLatestTimeline'), isNotEmpty);
    });

    test('init loads lastRefreshTime from prefs', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'x_query_ids_last_refresh': now,
      });

      await service.init();
      expect(service.lastRefreshTime, isNotNull);
    });
  });

  group('refreshQueryIds (HTTP)', () {
    late XQueryIdService svc;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      svc = XQueryIdService.instance;
      registerHttpFallbacks();
    });

    tearDown(() {
      svc.httpClientOverride = null;
    });

    test('parses queryIds from JS bundle HTML and JS', () async {
      await svc.clearCache();

      // HTML page with script tag pointing to JS bundle
      const htmlBody = '''
<html>
<head>
<script src="https://abs.twimg.com/responsive-web/client-web/main.abc123.js" nonce="x"></script>
</head>
<body></body>
</html>''';

      // JS bundle containing queryId patterns (with } delimiters like real minified JS)
      const jsBody = '''
some code{queryId:"NEW_QUERY_ID_1",operationName:"HomeLatestTimeline"}
more code{queryId:"NEW_QUERY_ID_2",operationName:"TweetDetail"}
even more code{operationName:"FavoriteTweet",some:stuff,queryId:"NEW_QUERY_ID_3"}
''';

      // Create a mock client that returns HTML for the first request
      // and JS for the second request
      final client = MockHttpClient();
      var callCount = 0;
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(htmlBody, 200);
        } else {
          return http.Response(jsBody, 200);
        }
      });
      svc.httpClientOverride = client;

      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final count = await svc.refreshQueryIds(creds);

      expect(count, greaterThan(0));
      expect(svc.getQueryId('HomeLatestTimeline'), 'NEW_QUERY_ID_1');
      expect(svc.getQueryId('TweetDetail'), 'NEW_QUERY_ID_2');
      expect(svc.getQueryId('FavoriteTweet'), 'NEW_QUERY_ID_3');
    });

    test('returns 0 when HTML fetch fails', () async {
      await svc.clearCache();

      final client = createMockClient(statusCode: 500, body: 'error');
      svc.httpClientOverride = client;

      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final count = await svc.refreshQueryIds(creds);

      expect(count, 0);
    });

    test('returns 0 when no script tags found', () async {
      await svc.clearCache();

      const htmlBody = '<html><body>no scripts here</body></html>';
      final client = createMockClient(statusCode: 200, body: htmlBody);
      svc.httpClientOverride = client;

      final creds = XCredentials(authToken: 'a', ct0: 'c');
      final count = await svc.refreshQueryIds(creds);

      expect(count, 0);
    });

    test('skips refresh when within rate limit interval', () async {
      await svc.clearCache();

      // First successful refresh
      const htmlBody = '''
<html>
<script src="https://abs.twimg.com/responsive-web/client-web/main.abc.js" nonce="x"></script>
</html>''';
      const jsBody = 'queryId:"ID1",operationName:"HomeLatestTimeline"';

      final client = MockHttpClient();
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((inv) async {
        final uri = inv.positionalArguments[0] as Uri;
        if (uri.host == 'x.com') return http.Response(htmlBody, 200);
        return http.Response(jsBody, 200);
      });
      svc.httpClientOverride = client;

      final creds = XCredentials(authToken: 'a', ct0: 'c');
      await svc.refreshQueryIds(creds);

      // Second call should be skipped due to rate limit
      final count2 = await svc.refreshQueryIds(creds);
      expect(count2, 0);
    });

    test('forceRefresh bypasses rate limit', () async {
      await svc.clearCache();

      const htmlBody = '''
<html>
<script src="https://abs.twimg.com/responsive-web/client-web/main.abc.js" nonce="x"></script>
</html>''';
      const jsBody = 'queryId:"FORCE_ID",operationName:"HomeLatestTimeline"';

      final client = MockHttpClient();
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((inv) async {
        final uri = inv.positionalArguments[0] as Uri;
        if (uri.host == 'x.com') return http.Response(htmlBody, 200);
        return http.Response(jsBody, 200);
      });
      svc.httpClientOverride = client;

      final creds = XCredentials(authToken: 'a', ct0: 'c');
      // First refresh
      await svc.refreshQueryIds(creds);

      // Force refresh should bypass rate limit
      final count = await svc.forceRefresh(creds);
      expect(count, greaterThan(0));
    });

    test('refreshQueryIds works with null creds', () async {
      await svc.clearCache();

      const htmlBody = '''
<html>
<script src="https://abs.twimg.com/responsive-web/client-web/main.abc.js" nonce="x"></script>
</html>''';
      const jsBody = 'queryId:"NULLCREDS_ID",operationName:"HomeLatestTimeline"';

      final client = MockHttpClient();
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((inv) async {
        final uri = inv.positionalArguments[0] as Uri;
        if (uri.host == 'x.com') return http.Response(htmlBody, 200);
        return http.Response(jsBody, 200);
      });
      svc.httpClientOverride = client;

      final count = await svc.refreshQueryIds(null);
      expect(count, greaterThan(0));
    });

    test('JS bundle fetch failure is handled gracefully', () async {
      await svc.clearCache();

      const htmlBody = '''
<html>
<script src="https://abs.twimg.com/responsive-web/client-web/main.abc.js" nonce="x"></script>
</html>''';

      final client = MockHttpClient();
      var callCount = 0;
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async {
        callCount++;
        if (callCount == 1) return http.Response(htmlBody, 200);
        return http.Response('', 404);
      });
      svc.httpClientOverride = client;

      final count = await svc.refreshQueryIds(null);
      expect(count, 0);
    });
  });
}
