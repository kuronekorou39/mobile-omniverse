import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// つながり調査の進み具合だけを残すログ。
///
/// 通信ログ (DebugLogService) は 1 リクエストごとに数 KB を書くため 5MB の
/// 上限にすぐ達し、古い方から捨てられる。つながり調査は数時間から数日かかる
/// ので、同じファイルに混ぜると調査の序盤が必ず消えてしまう。
///
/// こちらは 1 件あたり 1 行しか書かないので、同じ上限でも桁違いに長く残る。
/// 「調査がどこまで進んだか」「誰で失敗したか」を後から追うための記録なので、
/// 通信ログの ON/OFF とは無関係に常に書く。
class ScanLogService {
  ScanLogService._();
  static final instance = ScanLogService._();

  File? _logFile;
  int _logBytes = 0;

  /// 1 行 100 バイト前後なので、2MB あれば 2 万件近く残る
  static const int _maxLogSize = 2 * 1024 * 1024;

  /// ローテーション時に残すサイズ
  static const int _rotateKeepSize = 1024 * 1024;

  bool _isRotating = false;

  /// 起動時に 1 回呼ぶ
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/omniverse_scan.log');
    _logBytes = await _logFile!.exists() ? await _logFile!.length() : 0;
  }

  String? get logFilePath => _logFile?.path;

  int get logBytes => _logBytes;

  String get logSizeLabel {
    if (_logBytes < 1024) return '$_logBytes B';
    if (_logBytes < 1024 * 1024) {
      return '${(_logBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(_logBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 1 行追記する。時刻は行頭に付ける
  Future<void> log(String message) async {
    if (_logFile == null || _isRotating) return;
    final line = '${DateTime.now().toIso8601String()} $message\n';
    try {
      final bytes = utf8.encode(line);
      await _logFile!.writeAsBytes(bytes, mode: FileMode.append, flush: true);
      _logBytes += bytes.length;
      if (_logBytes > _maxLogSize) await _rotate();
    } catch (e) {
      debugPrint('[ScanLog] write error: $e');
    }
  }

  /// 末尾を残して切り詰める。行の途中で切らないよう改行位置で揃える
  Future<void> _rotate() async {
    if (_logFile == null || _isRotating) return;
    _isRotating = true;
    try {
      final content = await _logFile!.readAsString();
      final keepFrom = content.length - _rotateKeepSize;
      if (keepFrom > 0) {
        final newline = content.indexOf('\n', keepFrom);
        final trimmed =
            content.substring(newline >= 0 ? newline + 1 : keepFrom);
        await _logFile!.writeAsString(trimmed, mode: FileMode.write);
        _logBytes = utf8.encode(trimmed).length;
      }
    } catch (e) {
      debugPrint('[ScanLog] rotate error: $e');
      try {
        await _logFile!.writeAsString('', mode: FileMode.write);
        _logBytes = 0;
      } catch (_) {}
    } finally {
      _isRotating = false;
    }
  }

  Future<void> clear() async {
    if (_logFile == null) return;
    try {
      await _logFile!.writeAsString('', mode: FileMode.write);
      _logBytes = 0;
    } catch (e) {
      debugPrint('[ScanLog] clear error: $e');
    }
  }

  Future<String> readAll() async {
    if (_logFile == null || !await _logFile!.exists()) return '';
    return _logFile!.readAsString();
  }
}
