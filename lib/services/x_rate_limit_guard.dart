import 'package:flutter/foundation.dart';

import '../models/account.dart';

/// 429 が続いたエンドポイントを一定時間叩かないようにする。
///
/// X のレート制限は 15 分窓なので、制限に掛かった直後に何度リトライしても
/// 無駄で、むしろ窓が明けるのを遠ざける。429 を受けたら「アカウント×
/// オペレーション」単位でクールダウンを置き、その間はリクエスト自体を
/// 送らない。連続するほど待ち時間を伸ばし、成功したらリセットする。
class XRateLimitGuard {
  XRateLimitGuard._();
  static final instance = XRateLimitGuard._();

  /// 連続 429 の回数に対する待ち時間。以降は最後の値（X の窓と同じ 15 分）。
  static const _backoff = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  /// retry-after ヘッダを信用する上限。これを超える値は壊れているとみなす。
  static const _maxRetryAfter = Duration(minutes: 15);

  final Map<String, _Entry> _entries = {};

  static String keyFor(XCredentials creds, String operation) {
    final token = creds.authToken;
    final short = token.length > 8 ? token.substring(0, 8) : token;
    return '$short:$operation';
  }

  /// クールダウン中なら残り時間、そうでなければ null
  Duration? remaining(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    final left = entry.until.difference(DateTime.now());
    if (left <= Duration.zero) {
      // 期限切れ。連続回数は残して、次に 429 が来たら早めに伸ばす
      entry.until = DateTime.fromMillisecondsSinceEpoch(0);
      return null;
    }
    return left;
  }

  bool isCoolingDown(String key) => remaining(key) != null;

  /// 429 を受けたので待ちに入る。設定したクールダウンを返す。
  Duration recordRateLimited(String key, {Duration? retryAfter}) {
    final entry = _entries.putIfAbsent(key, _Entry.new);
    entry.strikes++;
    final backoff = _backoff[
        (entry.strikes - 1).clamp(0, _backoff.length - 1)];
    // retry-after が来ていて、しかもこちらの見積もりより長いなら従う
    final wait = (retryAfter != null && retryAfter > backoff)
        ? (retryAfter > _maxRetryAfter ? _maxRetryAfter : retryAfter)
        : backoff;
    entry.until = DateTime.now().add(wait);
    debugPrint('[XRateLimit] $key: ${wait.inMinutes}分待機 '
        '(${entry.strikes}回目)');
    return wait;
  }

  /// 通った。連続回数ごと忘れる。
  void recordSuccess(String key) {
    _entries.remove(key);
  }

  /// アカウント切替やログアウトなど、状態を引きずりたくないとき用
  void clear() => _entries.clear();

  /// デバッグ表示用。キー → 残り時間。
  Map<String, Duration> get activeCooldowns => {
        for (final entry in _entries.entries)
          if (remaining(entry.key) case final left?) entry.key: left,
      };
}

class _Entry {
  int strikes = 0;
  DateTime until = DateTime.fromMillisecondsSinceEpoch(0);
}
