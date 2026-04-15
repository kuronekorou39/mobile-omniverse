import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// メモリ使用量を監視し、閾値を超えたら自動で負荷軽減するサービス
class MemoryGuardService {
  MemoryGuardService._();
  static final instance = MemoryGuardService._();

  Timer? _timer;
  bool _precachePaused = false;

  /// プリキャッシュが一時停止中かどうか
  bool get isPrecachePaused => _precachePaused;

  /// 警告レベル（MB）: プリキャッシュ停止 + 画像キャッシュ半分クリア
  static const _warningMB = 800;
  /// 緊急レベル（MB）: 画像キャッシュ全クリア
  static const _criticalMB = 1000;
  /// 復帰レベル（MB）: プリキャッシュ再開
  static const _resumeMB = 600;

  /// 監視を開始（5秒間隔）
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _check() {
    final rssMB = ProcessInfo.currentRss / (1024 * 1024);

    if (rssMB >= _criticalMB) {
      // 緊急: 画像キャッシュ全クリア
      debugPrint('[MemoryGuard] CRITICAL: ${rssMB.round()}MB — clearing all image cache');
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      DefaultCacheManager().emptyCache();
      _precachePaused = true;
    } else if (rssMB >= _warningMB) {
      // 警告: プリキャッシュ停止 + 画像キャッシュ縮小
      if (!_precachePaused) {
        debugPrint('[MemoryGuard] WARNING: ${rssMB.round()}MB — pausing precache, trimming image cache');
        _precachePaused = true;
      }
      final cache = PaintingBinding.instance.imageCache;
      cache.maximumSize = (cache.maximumSize * 0.5).round().clamp(10, 1000);
    } else if (rssMB < _resumeMB && _precachePaused) {
      // 復帰
      debugPrint('[MemoryGuard] RESUMED: ${rssMB.round()}MB — resuming precache');
      _precachePaused = false;
    }
  }
}
