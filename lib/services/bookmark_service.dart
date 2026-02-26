import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/post.dart';

/// 投稿のブックマーク（ローカル保存）を管理するサービス
class BookmarkService {
  BookmarkService._();
  static final instance = BookmarkService._();

  static const _key = 'bookmarks';

  List<Post> _bookmarks = [];
  List<Post> get bookmarks => List.unmodifiable(_bookmarks);

  final Set<String> _bookmarkedIds = {};

  /// 初期化: SharedPreferences からブックマークをロード
  Future<void> init() async {
    _bookmarks = [];
    _bookmarkedIds.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;

      final list = json.decode(raw) as List<dynamic>;
      _bookmarks = list
          .map((item) => Post.fromCache(item as Map<String, dynamic>))
          .toList();
      _bookmarkedIds.addAll(_bookmarks.map((p) => p.id));
      debugPrint('[Bookmark] Loaded ${_bookmarks.length} bookmarks');
    } catch (e) {
      debugPrint('[Bookmark] Error loading: $e');
    }
  }

  /// テスト用: 内部状態をクリア
  @visibleForTesting
  void resetForTest() {
    _bookmarks = [];
    _bookmarkedIds.clear();
  }

  bool isBookmarked(String postId) => _bookmarkedIds.contains(postId);

  /// ブックマークの追加/解除をトグル
  Future<bool> toggle(Post post) async {
    if (_bookmarkedIds.contains(post.id)) {
      _bookmarks.removeWhere((p) => p.id == post.id);
      _bookmarkedIds.remove(post.id);
    } else {
      _bookmarks.insert(0, post);
      _bookmarkedIds.add(post.id);
    }
    await _save();
    return _bookmarkedIds.contains(post.id);
  }

  Future<void> _save() async {
    try {
      final data = _bookmarks.map((p) => p.toJson()).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, json.encode(data));
    } catch (e) {
      debugPrint('[Bookmark] Error saving: $e');
    }
  }
}
