import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/post.dart';

/// 投稿の下書き。
/// 失敗時に自動保存されるもの（failedAccountIds が空でない）と、
/// 編集中に明示保存されるもの（failedAccountIds が空）の 2 種類があるが、
/// データ構造としては同じ。
class Draft {
  const Draft({
    required this.id,
    required this.updatedAt,
    required this.text,
    this.inReplyToPost,
    this.quotedPost,
    this.failedAccountIds = const [],
  });

  final String id;
  final DateTime updatedAt;
  final String text;
  final Post? inReplyToPost;
  final Post? quotedPost;
  final List<String> failedAccountIds;

  bool get isFailureDraft => failedAccountIds.isNotEmpty;

  Draft copyWith({
    String? text,
    DateTime? updatedAt,
    List<String>? failedAccountIds,
  }) {
    return Draft(
      id: id,
      updatedAt: updatedAt ?? this.updatedAt,
      text: text ?? this.text,
      inReplyToPost: inReplyToPost,
      quotedPost: quotedPost,
      failedAccountIds: failedAccountIds ?? this.failedAccountIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'updatedAt': updatedAt.toIso8601String(),
        'text': text,
        if (inReplyToPost != null) 'inReplyToPost': inReplyToPost!.toJson(),
        if (quotedPost != null) 'quotedPost': quotedPost!.toJson(),
        'failedAccountIds': failedAccountIds,
      };

  static Draft? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final text = json['text'] as String?;
    if (id == null || text == null) return null;
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
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
      id: id,
      updatedAt: updatedAt,
      text: text,
      inReplyToPost: reply,
      quotedPost: quote,
      failedAccountIds: ids,
    );
  }

  /// 新規下書き用の id を生成する（衝突しないよう time + random）。
  static String newId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final r = Random().nextInt(1 << 32);
    return 'd_${ts}_$r';
  }
}

class DraftService {
  DraftService._();
  static final instance = DraftService._();

  static const _key = 'compose_drafts_v2';
  static const _legacyKey = 'compose_draft_v1';
  static const _maxDrafts = 100;

  Future<List<Draft>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // v1（単一下書き）の残骸は捨てる。マイグレーションはしない。
      if (prefs.containsKey(_legacyKey)) {
        await prefs.remove(_legacyKey);
      }
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      final drafts = <Draft>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final d = Draft.fromJson(item);
          if (d != null) drafts.add(d);
        }
      }
      drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return drafts;
    } catch (e) {
      debugPrint('[DraftService] loadAll failed: $e');
      return [];
    }
  }

  /// 既存 id があれば更新、無ければ追加。100 件超えたら最古を削除。
  Future<void> upsert(Draft draft) async {
    try {
      final list = await loadAll();
      list.removeWhere((d) => d.id == draft.id);
      list.insert(0, draft);
      if (list.length > _maxDrafts) {
        list.removeRange(_maxDrafts, list.length);
      }
      await _saveAll(list);
    } catch (e) {
      debugPrint('[DraftService] upsert failed: $e');
    }
  }

  Future<void> delete(String id) async {
    try {
      final list = await loadAll();
      list.removeWhere((d) => d.id == id);
      await _saveAll(list);
    } catch (e) {
      debugPrint('[DraftService] delete failed: $e');
    }
  }

  /// 失敗下書き（failedAccountIds が空でない）のうち最新 1 件。
  Future<Draft?> latestFailure() async {
    final list = await loadAll();
    for (final d in list) {
      if (d.isFailureDraft) return d;
    }
    return null;
  }

  Future<void> _saveAll(List<Draft> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(drafts.map((d) => d.toJson()).toList());
    await prefs.setString(_key, encoded);
  }
}
