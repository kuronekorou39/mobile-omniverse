import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../models/post.dart';

/// タイムラインのキャッシュをファイルに保存・復元するサービス
class TimelineCacheService {
  TimelineCacheService._();
  static final instance = TimelineCacheService._();

  static const _fileName = 'timeline_cache.json';
  static const _maxCachedPosts = 150;

  File? _cacheFile;

  @visibleForTesting
  File? cacheFileOverride;

  /// キャッシュファイルを取得
  Future<File> _getFile() async {
    if (cacheFileOverride != null) return cacheFileOverride!;
    if (_cacheFile != null) return _cacheFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cacheFile = File('${dir.path}/$_fileName');
    return _cacheFile!;
  }

  /// キャッシュからタイムラインを復元
  Future<List<Post>> loadCachedTimeline() async {
    try {
      final file = await _getFile();
      if (!file.existsSync()) return [];

      final raw = await file.readAsString();
      if (raw.isEmpty) return [];

      final list = json.decode(raw) as List<dynamic>;
      final posts = <Post>[];
      for (final item in list) {
        try {
          final post = Post.tryFromCache(item as Map<String, dynamic>);
          if (post != null) posts.add(post);
        } catch (e) {
          debugPrint('[TimelineCache] Error parsing cached post: $e');
        }
      }
      debugPrint('[TimelineCache] Loaded ${posts.length} cached posts');
      return posts;
    } catch (e) {
      debugPrint('[TimelineCache] Error loading cache: $e');
      return [];
    }
  }

  /// タイムラインをキャッシュに保存
  Future<void> saveTimeline(List<Post> posts) async {
    try {
      final file = await _getFile();
      final toSave = posts.take(_maxCachedPosts).toList();
      final data = toSave.map((p) => p.toJson()).toList();
      final encoded = json.encode(data);
      await file.writeAsString(encoded);
      debugPrint('[TimelineCache] Saved ${toSave.length} posts to cache');
    } catch (e) {
      debugPrint('[TimelineCache] Error saving cache: $e');
    }
  }

  /// キャッシュを消去
  Future<void> clearCache() async {
    try {
      final file = await _getFile();
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[TimelineCache] Error clearing cache: $e');
    }
  }
}
