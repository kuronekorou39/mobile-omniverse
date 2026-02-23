import 'sns_service.dart';

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
    this.isLiked = false,
    this.isReposted = false,
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
  });

  final String id;
  final SnsService source;
  final String username;
  final String handle;
  final String body;
  final DateTime timestamp;
  final String? avatarUrl;
  final String? accountId;

  // Engagement
  int likeCount;
  int replyCount;
  int repostCount;
  bool isLiked;
  bool isReposted;

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
    );
  }

  Post copyWith({
    int? likeCount,
    int? replyCount,
    int? repostCount,
    bool? isLiked,
    bool? isReposted,
    bool? isRetweet,
    String? retweetedByUsername,
    String? retweetedByHandle,
    Post? quotedPost,
  }) {
    return Post(
      id: id,
      source: source,
      username: username,
      handle: handle,
      body: body,
      timestamp: timestamp,
      avatarUrl: avatarUrl,
      accountId: accountId,
      likeCount: likeCount ?? this.likeCount,
      replyCount: replyCount ?? this.replyCount,
      repostCount: repostCount ?? this.repostCount,
      isLiked: isLiked ?? this.isLiked,
      isReposted: isReposted ?? this.isReposted,
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
        'isLiked': isLiked,
        'isReposted': isReposted,
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
        if (quotedPost != null) 'quotedPost': quotedPost!.toJson(),
      };

  factory Post.fromCache(Map<String, dynamic> json) {
    final source = SnsService.values.firstWhere(
      (s) => s.name == json['source'],
      orElse: () => SnsService.x,
    );
    return Post(
      id: json['id'] as String,
      source: source,
      username: json['username'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      body: json['body'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      avatarUrl: json['avatarUrl'] as String?,
      accountId: json['accountId'] as String?,
      likeCount: json['likeCount'] as int? ?? 0,
      replyCount: json['replyCount'] as int? ?? 0,
      repostCount: json['repostCount'] as int? ?? 0,
      isLiked: json['isLiked'] as bool? ?? false,
      isReposted: json['isReposted'] as bool? ?? false,
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
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Post && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
