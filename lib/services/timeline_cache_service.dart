import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/post.dart';

/// タイムラインのキャッシュを SharedPreferences に保存・復元するサービス
class TimelineCacheService {
  TimelineCacheService._();
  static final instance = TimelineCacheService._();

  static const _key = 'timeline_cache';
  static const _maxCachedPosts = 150;

  /// キャッシュからタイムラインを復元
  Future<List<Post>> loadCachedTimeline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];

      final list = json.decode(raw) as List<dynamic>;
      final posts = <Post>[];
      for (final item in list) {
        try {
          posts.add(Post.fromCache(item as Map<String, dynamic>));
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
      final toSave = posts.take(_maxCachedPosts).toList();
      final data = toSave.map((p) => p.toJson()).toList();
      final encoded = json.encode(data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encoded);
      debugPrint('[TimelineCache] Saved ${toSave.length} posts to cache');
    } catch (e) {
      debugPrint('[TimelineCache] Error saving cache: $e');
    }
  }

  /// キャッシュを消去
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
