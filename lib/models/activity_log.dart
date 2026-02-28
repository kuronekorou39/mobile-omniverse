import 'sns_service.dart';

enum ActivityAction {
  like,
  unlike,
  repost,
  unrepost,
  timelineFetch,
  follow,
  unfollow,
  post,
  profileFetch,
}

class ActivityLog {
  ActivityLog({
    required this.timestamp,
    required this.action,
    required this.platform,
    required this.accountHandle,
    this.accountId,
    this.targetId,
    this.targetSummary,
    required this.success,
    this.statusCode,
    this.errorMessage,
    this.responseSnippet,
  });

  final DateTime timestamp;
  final ActivityAction action;
  final SnsService platform;
  final String accountHandle;
  final String? accountId;

  /// 操作対象の ID (tweet ID, AT URI, etc.)
  final String? targetId;

  /// 操作対象の要約 (投稿の先頭テキスト等)
  final String? targetSummary;

  final bool success;
  final int? statusCode;
  final String? errorMessage;

  /// API レスポンスの先頭部分 (デバッグ用)
  final String? responseSnippet;

  String get actionLabel => switch (action) {
        ActivityAction.like => 'いいね',
        ActivityAction.unlike => 'いいね解除',
        ActivityAction.repost => 'リポスト',
        ActivityAction.unrepost => 'リポスト解除',
        ActivityAction.timelineFetch => 'TL取得',
        ActivityAction.follow => 'フォロー',
        ActivityAction.unfollow => 'フォロー解除',
        ActivityAction.post => '投稿',
        ActivityAction.profileFetch => 'プロフィール取得',
      };

  String get statusLabel => success ? 'OK' : 'FAIL';
}
