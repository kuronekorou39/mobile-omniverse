import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/widgets.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'debug_log_service.dart';

/// X の公開 Bearer Token を管理するサービス
/// SharedPreferences キャッシュ → JSバンドル自動取得
class XBearerTokenService {
  XBearerTokenService._();
  static final instance = XBearerTokenService._();

  @visibleForTesting
  http.Client? httpClientOverride;

  static const _prefsKey = 'x_bearer_token';

  String _current = '';
  String get token => _current;
  bool get hasToken => _current.isNotEmpty;

  DateTime? _lastRefresh;
  static const _refreshInterval = Duration(hours: 24);

  /// SharedPreferences からキャッシュを読み込み
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey);
    if (cached != null && cached.isNotEmpty) {
      _current = cached;
    }
  }

  /// Cookie付きで x.com の JS バンドルから Bearer Token を抽出
  Future<void> refresh({String? cookie, bool force = false}) async {
    if (!force && _lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < _refreshInterval) {
      return;
    }

    try {
      final client = httpClientOverride ?? http.Client();
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      };
      if (cookie != null) headers['Cookie'] = cookie;

      final response = await client.get(
        Uri.parse('https://x.com/home'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        DebugLogService.instance.log('XBearerToken', 'HTML fetch failed: ${response.statusCode}');
        return;
      }

      final scriptPattern = RegExp(
        r'<script[^>]+src="(https://abs\.twimg\.com/responsive-web/client-web[^"]*\.js)"',
      );

      for (final match in scriptPattern.allMatches(response.body)) {
        final jsUrl = match.group(1)!;
        try {
          final jsResp = await client.get(Uri.parse(jsUrl));
          if (jsResp.statusCode != 200) continue;

          final tokenPattern = RegExp(r'"(AAAAAAA[A-Za-z0-9%_-]{80,})"');
          final tokenMatch = tokenPattern.firstMatch(jsResp.body);
          if (tokenMatch != null) {
            _current = tokenMatch.group(1)!;
            _lastRefresh = DateTime.now();
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_prefsKey, _current);
            DebugLogService.instance.log('XBearerToken', 'Refreshed from JS bundle');
            return;
          }
        } catch (e) {
          DebugLogService.instance.log('XBearerToken', 'JS fetch error: $e');
        }
      }

      _lastRefresh = DateTime.now();
    } catch (e) {
      DebugLogService.instance.log('XBearerToken', 'Refresh error: $e');
    }
  }
}
