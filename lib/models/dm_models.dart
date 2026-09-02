/// DM（見る専）のモデル。
///
/// この機能は読み取り専用。X も Bluesky も「既読をつける」のは読み取りとは
/// 独立した書き込み API（X: mark_read / Bluesky: updateRead）で、この機能は
/// それを一切呼ばない。GET だけで実装しているため、開いても相手に既読は
/// つかず、自分の未読バッジも未読のまま残る。
library;

/// 会話の相手（自分以外の参加者）
class DmMember {
  const DmMember({
    required this.id,
    this.handle,
    this.displayName,
    this.avatarUrl,
  });

  /// X: user_id / Bluesky: did
  final String id;
  final String? handle;
  final String? displayName;
  final String? avatarUrl;

  /// 画面に出す名前。表示名 → ハンドル → id の順で埋める
  String get label => displayName?.isNotEmpty == true
      ? displayName!
      : (handle?.isNotEmpty == true ? handle! : id);
}

class DmConversation {
  const DmConversation({
    required this.id,
    required this.title,
    this.avatarUrl,
    this.isGroup = false,
    this.hasUnread = false,
    this.unreadCount,
    this.lastText = '',
    this.lastAt,
    this.isRequest = false,
    this.muted = false,
    this.members = const [],
  });

  final String id;
  final String title;
  final String? avatarUrl;
  final bool isGroup;
  final bool hasUnread;

  /// Bluesky のみ件数が来る。X は有無だけ
  final int? unreadCount;
  final String lastText;
  final DateTime? lastAt;

  /// X の「メッセージリクエスト」（untrusted な受信箱）
  final bool isRequest;
  final bool muted;

  /// 自分以外の参加者。グループでの発言者名の解決に使う
  final List<DmMember> members;

  DmMember? memberFor(String senderId) {
    for (final m in members) {
      if (m.id == senderId) return m;
    }
    return null;
  }
}

class DmMessage {
  const DmMessage({
    required this.id,
    required this.senderId,
    this.senderName,
    this.senderAvatarUrl,
    required this.text,
    this.sentAt,
    this.isMine = false,
    this.mediaUrl,
    this.attachmentLabel,
    this.quoteText,
    this.quoteAuthor,
    this.quoteHandle,
    this.quoteUrl,
  });

  final String id;
  final String senderId;
  final String? senderName;
  final String? senderAvatarUrl;
  final String text;
  final DateTime? sentAt;
  final bool isMine;

  /// 添付画像・動画サムネイル。X の DM 画像は認証ヘッダが必要
  final String? mediaUrl;

  /// 「画像」「動画」「GIF」「ポスト」など、本文の外にある添付の種別
  final String? attachmentLabel;

  /// 添付がポスト参照のとき、その中身（本文・作者・URL）
  final String? quoteText;
  final String? quoteAuthor;
  final String? quoteHandle;
  final String? quoteUrl;
}
