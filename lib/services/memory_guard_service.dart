import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'debug_log_service.dart';

/// OS のメモリプレッシャー通知に反応して負荷軽減・安全終了するサービス
/// ポーリングではなくイベント駆動
class MemoryGuardService with WidgetsBindingObserver {
  MemoryGuardService._();
  static final instance = MemoryGuardService._();

  bool _precachePaused = false;
  int _pressureCount = 0;

  /// プリキャッシュが一時停止中かどうか
  bool get isPrecachePaused => _precachePaused;

  /// 監視を開始（WidgetsBindingObserver として登録）
  void start() {
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
  }

  /// OS からメモリプレッシャー通知を受けたとき呼ばれる
  @override
  void didHaveMemoryPressure() {
    _pressureCount++;
    final rssMB = ProcessInfo.currentRss / (1024 * 1024);
    final imgCache = PaintingBinding.instance.imageCache;
    final snapshot = 'RSS:${rssMB.round()}MB '
        'IMG:${imgCache.currentSize}枚/${(imgCache.currentSizeBytes / 1024 / 1024).toStringAsFixed(1)}MB '
        'pressure:#$_pressureCount';
    debugPrint('[MemoryGuard] $snapshot');

    // DebugLogService が有効ならファイルにも記録（軽量な文字列のみ）
    DebugLogService.instance.log('MemoryGuard', snapshot);

    if (_pressureCount >= 3) {
      // 3回目以降: アプリを安全終了（フリーズ防止）
      debugPrint('[MemoryGuard] FATAL: repeated pressure — exiting app');
      DebugLogService.instance.log('MemoryGuard', 'FATAL: exiting app');
      SystemNavigator.pop();
      return;
    }

    // 1回目: プリキャッシュ停止 + 画像キャッシュクリア
    // 2回目: 全キャッシュクリア
    _precachePaused = true;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (_pressureCount >= 2) {
      DefaultCacheManager().emptyCache();
    }
  }
}
