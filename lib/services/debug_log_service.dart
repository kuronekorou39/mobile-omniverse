import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// アプリ内の全API通信を省略なしでファイルに記録するサービス。
/// PC接続なしでもログを蓄積し、あとでダウンロード可能。
class DebugLogService {
  DebugLogService._();
  static final instance = DebugLogService._();

  File? _logFile;
  int _logBytes = 0;

  /// ログサイズ警告コールバック（上限に近づいた時）
  void Function(String sizeLabel)? onLogSizeWarning;

  /// 初期化 (アプリ起動時に1回呼ぶ)
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/omniverse_debug.log');
    if (await _logFile!.exists()) {
      _logBytes = await _logFile!.length();
    } else {
      _logBytes = 0;
    }
    // 起動時に既存ログが上限超過ならローテーション
    if (_logBytes > _maxLogSize) {
      _rotate();
    }
  }

  /// 現在のログサイズ (bytes)
  int get logBytes => _logBytes;

  /// 人間が読みやすいサイズ表記
  String get logSizeLabel {
    if (_logBytes < 1024) return '$_logBytes B';
    if (_logBytes < 1024 * 1024) return '${(_logBytes / 1024).toStringAsFixed(1)} KB';
    if (_logBytes < _oneGb) return '${(_logBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(_logBytes / _oneGb).toStringAsFixed(2)} GB';
  }

  /// ログファイルのパス
  String? get logFilePath => _logFile?.path;

  /// HTTP リクエスト/レスポンスを記録
  Future<void> logHttp({
    required String tag,
    required String method,
    required String url,
    Map<String, String>? requestHeaders,
    String? requestBody,
    int? statusCode,
    Map<String, String>? responseHeaders,
    String? responseBody,
    String? error,
    Duration? duration,
    Map<String, dynamic>? extra,
  }) async {
    final buf = StringBuffer();
    final now = DateTime.now();
    buf.writeln('════════════════════════════════════════════════════════════');
    buf.writeln('[$tag] ${now.toIso8601String()}');
    buf.writeln('$method $url');
    if (duration != null) {
      buf.writeln('Duration: ${duration.inMilliseconds}ms');
    }
    buf.writeln('');

    if (requestHeaders != null && requestHeaders.isNotEmpty) {
      buf.writeln('── Request Headers ──');
      for (final e in requestHeaders.entries) {
        buf.writeln('${e.key}: ${e.value}');
      }
      buf.writeln('');
    }

    if (requestBody != null && requestBody.isNotEmpty) {
      buf.writeln('── Request Body ──');
      buf.writeln(requestBody);
      buf.writeln('');
    }

    if (statusCode != null) {
      buf.writeln('── Response Status: $statusCode ──');
    }

    if (responseHeaders != null && responseHeaders.isNotEmpty) {
      buf.writeln('── Response Headers ──');
      for (final e in responseHeaders.entries) {
        buf.writeln('${e.key}: ${e.value}');
      }
      buf.writeln('');
    }

    _appendTruncatedBody(buf, 'Response Body', responseBody);

    if (error != null) {
      buf.writeln('── Error ──');
      buf.writeln(error);
      buf.writeln('');
    }

    if (extra != null && extra.isNotEmpty) {
      buf.writeln('── Extra ──');
      for (final e in extra.entries) {
        buf.writeln('${e.key}: ${e.value}');
      }
      buf.writeln('');
    }

    await _append(buf.toString());
  }

  /// WebView の JS 実行結果を記録
  Future<void> logWebView({
    required String tag,
    required String operation,
    String? queryId,
    String? ct0,
    String? requestBody,
    String? jsRawResult,
    int? statusCode,
    String? responseBody,
    String? error,
    Duration? duration,
    Map<String, dynamic>? extra,
  }) async {
    final buf = StringBuffer();
    final now = DateTime.now();
    buf.writeln('════════════════════════════════════════════════════════════');
    buf.writeln('[$tag] ${now.toIso8601String()}');
    buf.writeln('WebView: $operation');
    if (queryId != null) buf.writeln('queryId: $queryId');
    if (ct0 != null) buf.writeln('ct0: $ct0');
    if (duration != null) {
      buf.writeln('Duration: ${duration.inMilliseconds}ms');
    }
    buf.writeln('');

    if (requestBody != null && requestBody.isNotEmpty) {
      buf.writeln('── Request Body ──');
      buf.writeln(requestBody);
      buf.writeln('');
    }

    _appendTruncatedBody(buf, 'JS Raw Result', jsRawResult);

    if (statusCode != null) {
      buf.writeln('── Response Status: $statusCode ──');
    }

    _appendTruncatedBody(buf, 'Response Body', responseBody);

    if (error != null) {
      buf.writeln('── Error ──');
      buf.writeln(error);
      buf.writeln('');
    }

    if (extra != null && extra.isNotEmpty) {
      buf.writeln('── Extra ──');
      for (final e in extra.entries) {
        buf.writeln('${e.key}: ${e.value}');
      }
      buf.writeln('');
    }

    await _append(buf.toString());
  }

  /// 汎用ログ
  Future<void> log(String tag, String message) async {
    final now = DateTime.now();
    await _append('[$tag] ${now.toIso8601String()} $message\n');
  }

  static const int _oneGb = 1024 * 1024 * 1024;
  static const int _maxBodyLog = 2048;

  /// ログファイルの上限サイズ（50MB）
  static const int _maxLogSize = 50 * 1024 * 1024;
  /// ローテーション時に保持するサイズ（40MB — 直近分を残す）
  static const int _rotateKeepSize = 40 * 1024 * 1024;
  bool _isRotating = false;

  /// 大きなボディを切り詰めてログに追加
  void _appendTruncatedBody(StringBuffer buf, String label, String? body) {
    if (body == null) return;
    buf.writeln('── $label ──');
    if (body.length > _maxBodyLog) {
      buf.writeln(body.substring(0, _maxBodyLog));
      buf.writeln('... [truncated: ${body.length} bytes total]');
    } else {
      buf.writeln(body);
    }
    buf.writeln('');
  }

  Future<void> _append(String text) async {
    if (_logFile == null) return;
    try {
      await _logFile!.writeAsString(text, mode: FileMode.append);
      _logBytes += text.length;
      // 上限超過でローテーション
      if (_logBytes > _maxLogSize && !_isRotating) {
        _rotate();
      }
    } catch (e) {
      debugPrint('[DebugLog] write error: $e');
    }
  }

  /// 古いログを切り捨てて直近分のみ保持
  Future<void> _rotate() async {
    if (_logFile == null || _isRotating) return;
    _isRotating = true;
    try {
      final content = await _logFile!.readAsString();
      if (content.length <= _rotateKeepSize) {
        _isRotating = false;
        return;
      }
      // _rotateKeepSize 分だけ末尾を残す
      final keepFrom = content.length - _rotateKeepSize;
      // エントリ区切り（═══）の位置まで進めて中途半端なエントリを避ける
      final separatorIndex = content.indexOf('═══', keepFrom);
      final cutAt = separatorIndex >= 0 ? separatorIndex : keepFrom;
      final trimmed = content.substring(cutAt);
      await _logFile!.writeAsString(trimmed, mode: FileMode.write);
      _logBytes = trimmed.length;
      debugPrint('[DebugLog] Rotated: kept ${logSizeLabel}');
      onLogSizeWarning?.call(logSizeLabel);
    } catch (e) {
      debugPrint('[DebugLog] rotate error: $e');
    } finally {
      _isRotating = false;
    }
  }

  /// ログをクリア
  Future<void> clear() async {
    if (_logFile == null) return;
    try {
      await _logFile!.writeAsString('', mode: FileMode.write);
      _logBytes = 0;
    } catch (e) {
      debugPrint('[DebugLog] clear error: $e');
    }
  }

  /// ログの全テキストを取得
  Future<String> readAll() async {
    if (_logFile == null || !await _logFile!.exists()) return '';
    return _logFile!.readAsString();
  }
}
