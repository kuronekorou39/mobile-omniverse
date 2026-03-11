import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/widgets.dart' show visibleForTesting;

/// X の公開 Bearer Token を管理するサービス
/// JS バンドルから動的に取得し、失敗時はデフォルト値にフォールバック
class XBearerTokenService {
  XBearerTokenService._();
  static final instance = XBearerTokenService._();

  @visibleForTesting
  http.Client? httpClientOverride;

  static const _defaultToken =
      'AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs'
      '%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA';

  String _current = _defaultToken;
  String get token => _current;

  DateTime? _lastRefresh;
  static const _refreshInterval = Duration(hours: 24);

  /// x.com の JS バンドルから Bearer Token を抽出
  Future<void> refresh() async {
    if (_lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < _refreshInterval) {
      return;
    }

    try {
      final client = httpClientOverride ?? http.Client();
      final response = await client.get(
        Uri.parse('https://x.com'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        },
      );

      if (response.statusCode != 200) return;

      // main.*.js から Bearer Token を探す
      final scriptPattern = RegExp(
        r'<script[^>]+src="(https://abs\.twimg\.com/responsive-web/client-web[^"]*\.js)"',
      );
      for (final match in scriptPattern.allMatches(response.body)) {
        final jsUrl = match.group(1)!;
        try {
          final jsResp = await client.get(Uri.parse(jsUrl));
          if (jsResp.statusCode != 200) continue;

          // "AAAAAAA..." パターン (X の Bearer Token は常に "AAAAAAA" で始まる)
          final tokenPattern = RegExp(r'"(AAAAAAA[A-Za-z0-9%_-]{80,})"');
          final tokenMatch = tokenPattern.firstMatch(jsResp.body);
          if (tokenMatch != null) {
            _current = tokenMatch.group(1)!;
            _lastRefresh = DateTime.now();
            debugPrint('[XBearerToken] Refreshed from JS bundle');
            return;
          }
        } catch (_) {}
      }

      _lastRefresh = DateTime.now();
    } catch (e) {
      debugPrint('[XBearerToken] Refresh error: $e');
    }
  }
}
