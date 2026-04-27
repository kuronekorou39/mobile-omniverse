import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/post.dart';

/// 投稿失敗時の下書き。
/// 通常の編集中の保存はしない。投稿一括処理で1件以上失敗したときのみ保存され、
/// バナーから再投稿するときに復元される。
class Draft {
  const Draft({
    required this.text,
    this.inReplyToPost,
    this.quotedPost,
    this.failedAccountIds = const [],
  });

  final String text;
  final Post? inReplyToPost;
  final Post? quotedPost;
  final List<String> failedAccountIds;

  Map<String, dynamic> toJson() => {
        'text': text,
        if (inReplyToPost != null) 'inReplyToPost': inReplyToPost!.toJson(),
        if (quotedPost != null) 'quotedPost': quotedPost!.toJson(),
        'failedAccountIds': failedAccountIds,
      };

  static Draft? fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String?;
    if (text == null) return null;
    Post? reply;
    Post? quote;
    final replyJson = json['inReplyToPost'];
    if (replyJson is Map<String, dynamic>) {
      reply = Post.tryFromCache(replyJson);
    }
    final quoteJson = json['quotedPost'];
    if (quoteJson is Map<String, dynamic>) {
      quote = Post.tryFromCache(quoteJson);
    }
    final ids = (json['failedAccountIds'] as List?)
            ?.map((e) => e as String)
            .toList() ??
        const <String>[];
    return Draft(
      text: text,
      inReplyToPost: reply,
      quotedPost: quote,
      failedAccountIds: ids,
    );
  }
}

class DraftService {
  DraftService._();
  static final instance = DraftService._();

  static const _key = 'compose_draft_v1';

  Future<void> save(Draft draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(draft.toJson()));
    } catch (e) {
      debugPrint('[DraftService] save failed: $e');
    }
  }

  Future<Draft?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return Draft.fromJson(json);
    } catch (e) {
      debugPrint('[DraftService] load failed: $e');
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      debugPrint('[DraftService] clear failed: $e');
    }
  }
}

