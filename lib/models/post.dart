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
  });

  final String id;
  final SnsService source;
  final String username;
  final String handle;
  final String body;
  final DateTime timestamp;
  final String? avatarUrl;
  final String? accountId;

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Post && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
