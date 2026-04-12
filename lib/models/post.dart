import 'sns_service.dart';

enum EngagementState { none, partial, all }

class Post {
  Post({
    required this.id,
    required this.source,
    required this.username,
    required this.handle,
    required this.body,
    required this.timestamp,
    this.avatarUrl,
    this.accountId,
    this.likeCount = 0,
    this.replyCount = 0,
    this.repostCount = 0,
    this.imageUrls = const [],
    this.videoUrl,
    this.videoThumbnailUrl,
    this.permalink,
    this.inReplyToId,
    this.uri,
    this.cid,
    this.isRetweet = false,
    this.retweetedByUsername,
    this.retweetedByHandle,
    this.quotedPost,
    this.isSensitive = false,
    Set<String>? likedByAccountIds,
    Set<String>? repostedByAccountIds,
    Map<String, String>? bskyLikeUris,
    Map<String, String>? bskyRepostUris,
    Set<String>? fetchedByAccountIds,
  })  : likedByAccountIds = likedByAccountIds ?? {},
        repostedByAccountIds = repostedByAccountIds ?? {},
        bskyLikeUris = bskyLikeUris ?? {},
        bskyRepostUris = bskyRepostUris ?? {},
        fetchedByAccountIds = fetchedByAccountIds ??
            (accountId != null ? {accountId} : {});

  final String id;
  final SnsService source;
  final String username;
  final String handle;
  final String body;
  final DateTime timestamp;
  final String? avatarUrl;
  final String? accountId;

  // Engagement counts (global)
  int likeCount;
  int replyCount;
  int repostCount;

  // Per-account engagement state
  final Set<String> likedByAccountIds;
  final Set<String> repostedByAccountIds;

  // Bluesky viewer URIs per account (for unlike/unrepost)
  final Map<String, String> bskyLikeUris;
  final Map<String, String> bskyRepostUris;

  // Media
  final List<String> imageUrls;
  final String? videoUrl;
  final String? videoThumbnailUrl;

  // Metadata
  final String? permalink;
  final String? inReplyToId;

  // Platform-specific identifiers (for API operations)
  final String? uri; // Bluesky AT URI
  final String? cid; // Bluesky CID

  // RT / Quote
  final bool isRetweet;
  final String? retweetedByUsername;
  final String? retweetedByHandle;
  final Post? quotedPost;

  // Sensitive content flag
  final bool isSensitive;

  // 取得元アカウントID一覧（マージ時に蓄積）
  final Set<String> fetchedByAccountIds;

  // --- Engagement helpers ---

  bool get isLiked => likedByAccountIds.isNotEmpty;
  bool get isReposted => repostedByAccountIds.isNotEmpty;

  bool isLikedBy(String accountId) => likedByAccountIds.contains(accountId);
  bool isRepostedBy(String accountId) => repostedByAccountIds.contains(accountId);

  String? bskyLikeUriFor(String accountId) => bskyLikeUris[accountId];
  String? bskyRepostUriFor(String accountId) => bskyRepostUris[accountId];

  EngagementState likeState() {
    if (fetchedByAccountIds.isEmpty) {
      return likedByAccountIds.isNotEmpty ? EngagementState.all : EngagementState.none;
    }
    final count = fetchedByAccountIds.intersection(likedByAccountIds).length;
    if (count == 0) return EngagementState.none;
    if (count == fetchedByAccountIds.length) return EngagementState.all;
    return EngagementState.partial;
  }

  EngagementState repostState() {
    if (fetchedByAccountIds.isEmpty) {
      return repostedByAccountIds.isNotEmpty ? EngagementState.all : EngagementState.none;
    }
    final count = fetchedByAccountIds.intersection(repostedByAccountIds).length;
    if (count == 0) return EngagementState.none;
    if (count == fetchedByAccountIds.length) return EngagementState.all;
    return EngagementState.partial;
  }

  factory Post.fromJson(Map<String, dynamic> json, SnsService source,
      {String? accountId}) {
    return Post(
      id: json['id'] as String? ?? '${source.name}_${json.hashCode}',
      source: source,
      username: json['username'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      body: json['body'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      avatarUrl: json['avatarUrl'] as String?,
      accountId: accountId,
      isSensitive: json['isSensitive'] as bool? ?? false,
    );
  }

  Post copyWith({
    String? username,
    String? handle,
    String? avatarUrl,
    DateTime? timestamp,
    int? likeCount,
    int? replyCount,
    int? repostCount,
    Set<String>? likedByAccountIds,
    Set<String>? repostedByAccountIds,
    Map<String, String>? bskyLikeUris,
    Map<String, String>? bskyRepostUris,
    bool? isRetweet,
    String? retweetedByUsername,
    String? retweetedByHandle,
    Post? quotedPost,
    bool? isSensitive,
    Set<String>? fetchedByAccountIds,
  }) {
    return Post(
      id: id,
      source: source,
      username: username ?? this.username,
      handle: handle ?? this.handle,
      body: body,
      timestamp: timestamp ?? this.timestamp,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      accountId: accountId,
      likeCount: likeCount ?? this.likeCount,
      replyCount: replyCount ?? this.replyCount,
      repostCount: repostCount ?? this.repostCount,
      likedByAccountIds: likedByAccountIds ?? this.likedByAccountIds,
      repostedByAccountIds: repostedByAccountIds ?? this.repostedByAccountIds,
      bskyLikeUris: bskyLikeUris ?? this.bskyLikeUris,
      bskyRepostUris: bskyRepostUris ?? this.bskyRepostUris,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      videoThumbnailUrl: videoThumbnailUrl,
      permalink: permalink,
      inReplyToId: inReplyToId,
      uri: uri,
      cid: cid,
      isRetweet: isRetweet ?? this.isRetweet,
      retweetedByUsername: retweetedByUsername ?? this.retweetedByUsername,
      retweetedByHandle: retweetedByHandle ?? this.retweetedByHandle,
      quotedPost: quotedPost ?? this.quotedPost,
      isSensitive: isSensitive ?? this.isSensitive,
      fetchedByAccountIds: fetchedByAccountIds ?? this.fetchedByAccountIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'username': username,
        'handle': handle,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        'avatarUrl': avatarUrl,
        'accountId': accountId,
        'likeCount': likeCount,
        'replyCount': replyCount,
        'repostCount': repostCount,
        'likedByAccountIds': likedByAccountIds.toList(),
        'repostedByAccountIds': repostedByAccountIds.toList(),
        'bskyLikeUris': bskyLikeUris,
        'bskyRepostUris': bskyRepostUris,
        'imageUrls': imageUrls,
        'videoUrl': videoUrl,
        'videoThumbnailUrl': videoThumbnailUrl,
        'permalink': permalink,
        'inReplyToId': inReplyToId,
        'uri': uri,
        'cid': cid,
        'isRetweet': isRetweet,
        'retweetedByUsername': retweetedByUsername,
        'retweetedByHandle': retweetedByHandle,
        'isSensitive': isSensitive,
        'fetchedByAccountIds': fetchedByAccountIds.toList(),
        if (quotedPost != null) 'quotedPost': quotedPost!.toJson(),
      };

  /// キャッシュからの復元。タイムスタンプが不正な場合はnullを返す。
  static Post? tryFromCache(Map<String, dynamic> json) {
    final ts = DateTime.tryParse(json['timestamp'] as String? ?? '');
    if (ts == null) return null; // タイムスタンプ不正 → 破棄
    return Post.fromCache(json);
  }

  factory Post.fromCache(Map<String, dynamic> json) {
    final source = SnsService.values.firstWhere(
      (s) => s.name == json['source'],
      orElse: () => SnsService.x,
    );
    final cacheAccountId = json['accountId'] as String?;
    return Post(
      id: json['id'] as String,
      source: source,
      username: json['username'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      body: json['body'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      avatarUrl: json['avatarUrl'] as String?,
      accountId: cacheAccountId,
      likeCount: json['likeCount'] as int? ?? 0,
      replyCount: json['replyCount'] as int? ?? 0,
      repostCount: json['repostCount'] as int? ?? 0,
      // New format, with old format fallback
      likedByAccountIds: (json['likedByAccountIds'] as List<dynamic>?)
              ?.map((e) => e as String).toSet()
          ?? ((json['isLiked'] as bool? ?? false) && cacheAccountId != null
              ? {cacheAccountId} : {}),
      repostedByAccountIds: (json['repostedByAccountIds'] as List<dynamic>?)
              ?.map((e) => e as String).toSet()
          ?? ((json['isReposted'] as bool? ?? false) && cacheAccountId != null
              ? {cacheAccountId} : {}),
      bskyLikeUris: (json['bskyLikeUris'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String))
          ?? (json['bskyLikeUri'] != null && cacheAccountId != null
              ? {cacheAccountId: json['bskyLikeUri'] as String} : {}),
      bskyRepostUris: (json['bskyRepostUris'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String))
          ?? (json['bskyRepostUri'] != null && cacheAccountId != null
              ? {cacheAccountId: json['bskyRepostUri'] as String} : {}),
      imageUrls: (json['imageUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      videoUrl: json['videoUrl'] as String?,
      videoThumbnailUrl: json['videoThumbnailUrl'] as String?,
      permalink: json['permalink'] as String?,
      inReplyToId: json['inReplyToId'] as String?,
      uri: json['uri'] as String?,
      cid: json['cid'] as String?,
      isRetweet: json['isRetweet'] as bool? ?? false,
      retweetedByUsername: json['retweetedByUsername'] as String?,
      retweetedByHandle: json['retweetedByHandle'] as String?,
      quotedPost: json['quotedPost'] != null
          ? Post.fromCache(json['quotedPost'] as Map<String, dynamic>)
          : null,
      isSensitive: json['isSensitive'] as bool? ?? false,
      fetchedByAccountIds: (json['fetchedByAccountIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Post && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
