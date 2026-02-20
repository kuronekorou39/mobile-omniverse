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
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Post && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
