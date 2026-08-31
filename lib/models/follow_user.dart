/// フォロー/フォロワー一覧に現れる 1 ユーザー
///
/// X の GraphQL は同じ項目を `core` (新) と `legacy` (旧) の両方に
/// 置くことがあり、A/B テストでどちらかが欠けるため両方から読む。
class FollowUser {
  const FollowUser({
    required this.restId,
    required this.screenName,
    required this.name,
    this.followersCount = 0,
    this.friendsCount = 0,
    this.statusesCount,
    this.avatarUrl = '',
    this.description = '',
    this.verified = false,
    this.isProtected = false,
    this.location = '',
    this.createdAt = '',
    this.blockedBy,
    this.blocking,
    this.muting,
  });

  final String restId;
  final String screenName;
  final String name;
  final int followersCount;
  final int friendsCount;
  final int? statusesCount;
  final String avatarUrl;
  final String description;
  final bool verified;
  final bool isProtected;
  final String location;

  /// X が返す生文字列 (例: "Thu Apr 06 15:24:15 +0000 2023")
  final String createdAt;

  /// 一覧を取得したアカウントから見た関係 (relationship_perspectives)。
  ///
  /// **取得したアカウントに依存する**値なので、users には持たせず
  /// スナップショット側に保存する。項目が返らなかったときは null。
  /// 相手が自分をブロックしている
  final bool? blockedBy;

  /// 自分が相手をブロックしている
  final bool? blocking;

  /// 自分が相手をミュートしている
  final bool? muting;

  /// フォロワー数 / フォロー数。フォロー 0 は比が定義できないので null
  double? get followRatio =>
      friendsCount > 0 ? followersCount / friendsCount : null;

  /// GraphQL の user_results.result を 1 件パースする
  /// 必須項目 (restId / screenName) が欠けていたら null
  /// X はユーザーの項目を `legacy` から `core` / `avatar` / `privacy` /
  /// `profile_bio` / `location` / `verification` / `relationship_counts` へ
  /// 段階的に移している。どちらに入っていても拾えるよう両方見る。
  static FollowUser? fromUserResult(Map<String, dynamic>? result) {
    if (result == null) return null;

    final legacy = _asMap(result['legacy']);
    final core = _asMap(result['core']);
    final privacy = _asMap(result['privacy']);
    final avatar = _asMap(result['avatar']);
    final profileBio = _asMap(result['profile_bio']);
    final verification = _asMap(result['verification']);
    final counts = _asMap(result['relationship_counts']);
    final tweetCounts = _asMap(result['tweet_counts']);
    // 閲覧アカウントから見た関係。一覧にもそのまま載る
    final perspectives = _asMap(result['relationship_perspectives']);
    final locationObj = _asMap(result['location']);

    final restId = _str(result['rest_id']);
    final screenName = _str(core['screen_name']) ?? _str(legacy['screen_name']);
    if (restId == null || restId.isEmpty) return null;
    if (screenName == null || screenName.isEmpty) return null;

    return FollowUser(
      restId: restId,
      screenName: screenName,
      name: _str(core['name']) ?? _str(legacy['name']) ?? '',
      followersCount: _asInt(legacy['followers_count']) ??
          _asInt(counts['followers']) ??
          0,
      friendsCount:
          _asInt(legacy['friends_count']) ?? _asInt(counts['following']) ?? 0,
      // legacy が空の相手が実際に居る (X が新形式へ移し終えたアカウント)。
      // ここを legacy だけで読んでいたため投稿数が丸ごと欠けていた
      statusesCount: _asInt(legacy['statuses_count']) ??
          _asInt(tweetCounts['tweets']) ??
          _asInt(tweetCounts['tweet_count']),
      avatarUrl: _str(avatar['image_url']) ??
          _str(legacy['profile_image_url_https']) ??
          '',
      description:
          _str(legacy['description']) ?? _str(profileBio['description']) ?? '',
      verified: (legacy['verified'] as bool?) ??
          (verification['verified'] as bool?) ??
          (result['is_blue_verified'] as bool?) ??
          false,
      isProtected: (privacy['protected'] as bool?) ??
          (legacy['protected'] as bool?) ??
          false,
      location: _str(legacy['location']) ?? _str(locationObj['location']) ?? '',
      createdAt: _str(legacy['created_at']) ?? _str(core['created_at']) ?? '',
      blockedBy: perspectives['blocked_by'] as bool? ??
          legacy['blocked_by'] as bool?,
      blocking:
          perspectives['blocking'] as bool? ?? legacy['blocking'] as bool?,
      muting: perspectives['muting'] as bool? ?? legacy['muting'] as bool?,
    );
  }

  /// Bluesky の profileView / profileViewDetailed を 1 件パースする。
  ///
  /// 一覧の API (getFollows / getFollowers) が返すのは profileView で、
  /// フォロワー数・フォロー数・投稿数は入っていない。件数は
  /// app.bsky.actor.getProfiles でまとめて取り直して補う。
  static FollowUser? fromBlueskyProfile(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    final did = _str(profile['did']);
    final handle = _str(profile['handle']);
    if (did == null || did.isEmpty) return null;
    if (handle == null || handle.isEmpty) return null;

    return FollowUser(
      restId: did,
      screenName: handle,
      name: _str(profile['displayName']) ?? '',
      followersCount: _asInt(profile['followersCount']) ?? 0,
      friendsCount: _asInt(profile['followsCount']) ?? 0,
      statusesCount: _asInt(profile['postsCount']),
      avatarUrl: _str(profile['avatar']) ?? '',
      description: _str(profile['description']) ?? '',
      verified: _asMap(profile['verification'])['verifiedStatus'] == 'valid',
      // Bluesky に鍵アカウントの概念は無い
      isProtected: false,
      location: '',
      createdAt: _str(profile['createdAt']) ?? '',
    );
  }

  /// 件数だけを [detailed] の値で差し替える。
  /// 一覧で得たプロフィールに、あとから取った件数を載せるために使う。
  FollowUser withCountsFrom(FollowUser detailed) => FollowUser(
        restId: restId,
        screenName: screenName,
        name: name,
        followersCount: detailed.followersCount,
        friendsCount: detailed.friendsCount,
        statusesCount: detailed.statusesCount,
        avatarUrl: avatarUrl,
        description: description,
        verified: verified,
        isProtected: isProtected,
        location: location,
        createdAt: createdAt,
        blockedBy: blockedBy,
        blocking: blocking,
        muting: muting,
      );

  Map<String, dynamic> toJson() => {
        'restId': restId,
        'screenName': screenName,
        'name': name,
        'followersCount': followersCount,
        'friendsCount': friendsCount,
        'statusesCount': statusesCount,
        'avatarUrl': avatarUrl,
        'description': description,
        'verified': verified,
        'isProtected': isProtected,
        'location': location,
        'createdAt': createdAt,
        'blockedBy': blockedBy,
        'blocking': blocking,
        'muting': muting,
      };

  factory FollowUser.fromJson(Map<String, dynamic> map) => FollowUser(
        restId: map['restId'] as String,
        screenName: map['screenName'] as String,
        name: (map['name'] as String?) ?? '',
        followersCount: _asInt(map['followersCount']) ?? 0,
        friendsCount: _asInt(map['friendsCount']) ?? 0,
        statusesCount: _asInt(map['statusesCount']),
        avatarUrl: (map['avatarUrl'] as String?) ?? '',
        description: (map['description'] as String?) ?? '',
        verified: (map['verified'] as bool?) ?? false,
        isProtected: (map['isProtected'] as bool?) ?? false,
        location: (map['location'] as String?) ?? '',
        createdAt: (map['createdAt'] as String?) ?? '',
        blockedBy: map['blockedBy'] as bool?,
        blocking: map['blocking'] as bool?,
        muting: map['muting'] as bool?,
      );

  @override
  String toString() => 'FollowUser(@$screenName, $restId)';
}

/// 期待した型でないときに落ちないようにする (location が文字列だったり
/// オブジェクトだったりと、X 側の移行途中で型が揺れるため)
String? _str(Object? value) => value is String ? value : null;

Map<String, dynamic> _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
