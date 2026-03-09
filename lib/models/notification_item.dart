import 'sns_service.dart';

enum NotificationType {
  like,
  repost,
  reply,
  follow,
  mention,
  quote,
  unknown,
}

/// 通知アイテム (X / Bluesky 共通)
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.source,
    required this.actorName,
    required this.actorHandle,
    required this.timestamp,
    this.actorAvatarUrl,
    this.targetPostBody,
    this.targetPostId,
    this.isRead = false,
  });

  final String id;
  final NotificationType type;
  final SnsService source;

  /// アクションを行ったユーザー
  final String actorName;
  final String actorHandle;
  final String? actorAvatarUrl;

  /// 対象の投稿 (いいね・RT・リプライ等の場合)
  final String? targetPostBody;
  final String? targetPostId;

  final DateTime timestamp;
  final bool isRead;

  String get typeLabel => switch (type) {
        NotificationType.like => 'いいね',
        NotificationType.repost => 'リポスト',
        NotificationType.reply => 'リプライ',
        NotificationType.follow => 'フォロー',
        NotificationType.mention => 'メンション',
        NotificationType.quote => '引用',
        NotificationType.unknown => '通知',
      };
}
