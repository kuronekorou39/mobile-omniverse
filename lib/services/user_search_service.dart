import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/follow_user.dart';
import '../models/sns_service.dart';
import 'bluesky_api_service.dart';
import 'x_api_service.dart';

/// ユーザー検索。サービスごとに「どこまで探せるか」が違う
///
/// - **X**: ハンドル完全一致で 1 件引くだけ。名前やプロフィール文からの
///   検索 (SearchTimeline) は queryId と features が揃わないと 404 になる
///   ため、ここでは扱わない
/// - **Bluesky**: searchActors がハンドル・表示名・プロフィール文を見る
class UserSearchService {
  UserSearchService._();
  static final instance = UserSearchService._();

  @visibleForTesting
  XApiService xApi = XApiService.instance;

  @visibleForTesting
  BlueskyApiService blueskyApi = BlueskyApiService.instance;

  /// 入力からハンドルだけを取り出す。
  ///
  /// `@name` / `x.com/name` / `bsky.app/profile/name` / 投稿 URL の貼り付けを
  /// そのまま受けられるようにする。取り出せなければ空文字。
  static String normalizeHandle(String input) {
    var s = input.trim();
    if (s.isEmpty) return '';

    // URL ごと貼られたとき。scheme の有無どちらも受ける
    final urlMatch = RegExp(
      r'^(?:https?://)?(?:www\.)?'
      r'(?:x\.com|twitter\.com|bsky\.app)/'
      r'(?:profile/)?'
      r'([^/?#\s]+)',
      caseSensitive: false,
    ).firstMatch(s);
    if (urlMatch != null) {
      s = urlMatch.group(1)!;
    }

    s = s.replaceFirst(RegExp(r'^@+'), '');
    // クエリ文字列やスラッシュが残っていたら落とす
    s = s.split(RegExp(r'[/?#\s]')).first;
    return s;
  }

  /// [account] の資格情報で [query] を検索する。
  ///
  /// 見つからなければ空リスト。認証や通信の失敗は例外のまま投げる。
  Future<List<FollowUser>> search(Account account, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    return switch (account.service) {
      SnsService.x => _searchX(account, trimmed),
      SnsService.bluesky => _searchBluesky(account, trimmed),
    };
  }

  /// X はハンドル完全一致のみ。1 件か 0 件しか返らない
  Future<List<FollowUser>> _searchX(Account account, String query) async {
    final handle = normalizeHandle(query);
    if (handle.isEmpty) return const [];

    final profile = await xApi.getUserProfile(account.xCredentials, handle);
    final user = fromXProfileMap(profile);
    return user == null ? const [] : [user];
  }

  Future<List<FollowUser>> _searchBluesky(Account account, String query) async {
    return blueskyApi.searchActors(
        account.blueskyCredentials, fullTextQuery(query));
  }

  /// 全文検索に渡す文字列。
  ///
  /// `@name` や URL を貼られたときだけハンドルに直す。ふつうの語句は
  /// そのまま通す — スペース込みの表示名で探せなくなるため。
  static String fullTextQuery(String input) {
    final s = input.trim();
    if (!looksLikeHandleInput(s)) return s;
    final handle = normalizeHandle(s);
    return handle.isEmpty ? s : handle;
  }

  /// 「これはハンドルか URL の貼り付けだ」と言える形か
  static bool looksLikeHandleInput(String input) {
    final s = input.trim();
    if (s.startsWith('@')) return true;
    return RegExp(
      r'^(?:https?://)?(?:www\.)?(?:x\.com|twitter\.com|bsky\.app)/',
      caseSensitive: false,
    ).hasMatch(s);
  }

  /// XApiService.getUserProfile が返す正規化済み Map を FollowUser にする。
  /// GraphQL の生 result ではないので FollowUser.fromUserResult は使えない
  static FollowUser? fromXProfileMap(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    final restId = profile['rest_id'];
    final screenName = profile['screen_name'];
    if (restId is! String || restId.isEmpty) return null;
    if (screenName is! String || screenName.isEmpty) return null;

    int asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
    String asStr(Object? v) => v is String ? v : '';

    return FollowUser(
      restId: restId,
      screenName: screenName,
      name: asStr(profile['name']),
      followersCount: asInt(profile['followers_count']),
      friendsCount: asInt(profile['friends_count']),
      statusesCount: asInt(profile['statuses_count']),
      avatarUrl: asStr(profile['profile_image_url_https']),
      description: asStr(profile['description']),
      isProtected: profile['protected'] as bool? ?? false,
    );
  }
}
