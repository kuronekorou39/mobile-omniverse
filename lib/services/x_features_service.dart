import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GraphQL features パラメータを動的に管理するサービス
/// WebView からキャプチャした値を SharedPreferences にキャッシュ
class XFeaturesService {
  XFeaturesService._();
  static final instance = XFeaturesService._();

  static const _prefsKey = 'x_features_cache';

  // operationName -> features map
  final Map<String, Map<String, dynamic>> _cached = {};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null) {
      try {
        final outer = json.decode(stored) as Map<String, dynamic>;
        for (final entry in outer.entries) {
          _cached[entry.key] = Map<String, dynamic>.from(entry.value as Map);
        }
      } catch (_) {}
    }
  }

  /// operationName に対応する features を取得
  /// キャッシュにあればそれを返す、なければ null
  Map<String, dynamic>? getFeatures(String operationName) {
    return _cached[operationName];
  }

  /// WebView 等で取得した features を保存
  Future<void> updateFeatures(String operationName, Map<String, dynamic> features) async {
    _cached[operationName] = features;
    await _saveToPrefs();
    debugPrint('[XFeatures] Updated features for $operationName (${features.length} keys)');
  }

  /// 複数の features をまとめて保存
  Future<void> updateAll(Map<String, Map<String, dynamic>> allFeatures) async {
    _cached.addAll(allFeatures);
    await _saveToPrefs();
  }

  /// 現在のキャッシュ状態を取得（デバッグ用）
  Map<String, Map<String, dynamic>> get currentCache => Map.unmodifiable(_cached);

  /// キャッシュを全消去
  Future<void> clearCache() async {
    _cached.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, json.encode(_cached));
  }
}
