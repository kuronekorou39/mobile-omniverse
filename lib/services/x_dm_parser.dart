import '../models/dm_models.dart';

/// X の DM API（1.1 系）の応答を画面用のモデルにならす。
///
/// inbox_initial_state.json / inbox_timeline/&lt;trusted&gt;.json /
/// conversation/&lt;id&gt;.json はどれも同じ部品
/// （entries + users + conversations）でできているので、まとめて扱う。
///
/// 読み取り専用の方針どおり、ここで扱うのは GET の応答だけ。
class XDmParser {
  XDmParser._();

  /// 受信箱（inbox_initial_state / inbox_timeline）を会話一覧にならす。
  ///
  /// [selfUserId] は自分のメッセージ判定と未読判定に使う。分からなければ
  /// [selfHandle] から users マップを引いて解決する。
  static XDmInboxPage parseInbox(
    Map<String, dynamic> payload, {
    String? selfUserId,
    String? selfHandle,
  }) {
    final users = _usersOf(payload);
    final self = selfUserId ?? _resolveSelfId(users, selfHandle);
    final messages = _parseMessages(payload, users, self);

    // 会話ごとの最新メッセージ（entries は新しい順で来る）
    final latestByConvo = <String, DmMessage>{};
    final convoOfMessage = <String, String>{};
    for (final e in _entriesOf(payload)) {
      final message = e['message'];
      if (message is! Map<String, dynamic>) continue;
      final convoId = message['conversation_id'] as String?;
      final msgId =
          (message['message_data'] as Map<String, dynamic>?)?['id'] as String? ??
              message['id'] as String?;
      if (convoId == null || msgId == null) continue;
      convoOfMessage[msgId] = convoId;
    }
    for (final m in messages) {
      final convoId = convoOfMessage[m.id];
      if (convoId == null) continue;
      final prev = latestByConvo[convoId];
      if (prev == null ||
          (m.sentAt != null &&
              (prev.sentAt == null || m.sentAt!.isAfter(prev.sentAt!)))) {
        latestByConvo[convoId] = m;
      }
    }

    final conversations = <DmConversation>[];
    final convosRaw = payload['conversations'];
    if (convosRaw is Map<String, dynamic>) {
      for (final entry in convosRaw.entries) {
        final c = entry.value;
        if (c is! Map<String, dynamic>) continue;
        conversations.add(_parseConversation(
            entry.key, c, users, self, latestByConvo[entry.key]));
      }
    }
    conversations.sort((a, b) {
      final at = a.lastAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.lastAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });

    // 初期状態は inbox_timelines の中に、続きページ（inbox_timeline）は
    // トップレベルに、それぞれカーソルが入っている
    return XDmInboxPage(
      conversations: conversations,
      trustedNextMaxId: _timelineCursor(payload, 'trusted'),
      untrustedNextMaxId: _timelineCursor(payload, 'untrusted'),
      nextMaxId: payload['status'] == 'AT_END'
          ? null
          : payload['min_entry_id'] as String?,
      selfUserId: self,
    );
  }

  /// スレッド（conversation/&lt;id&gt;.json）をメッセージ一覧にならす。新しい順
  static XDmThreadPage parseThread(
    Map<String, dynamic> payload, {
    String? selfUserId,
    String? selfHandle,
  }) {
    final users = _usersOf(payload);
    final self = selfUserId ?? _resolveSelfId(users, selfHandle);
    final messages = _parseMessages(payload, users, self)
      ..sort((a, b) {
        final at = a.sentAt?.millisecondsSinceEpoch ?? 0;
        final bt = b.sentAt?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

    // status が AT_END なら min_entry_id が残っていてもそれより前は無い
    final status = payload['status'] as String?;
    final minEntryId = payload['min_entry_id'] as String?;
    return XDmThreadPage(
      messages: messages,
      nextMaxId: status == 'AT_END' ? null : minEntryId,
    );
  }

  // ─── 内部 ───

  static Map<String, dynamic> _usersOf(Map<String, dynamic> payload) {
    final u = payload['users'];
    return u is Map<String, dynamic> ? u : const {};
  }

  static List<Map<String, dynamic>> _entriesOf(Map<String, dynamic> payload) {
    final e = payload['entries'];
    if (e is! List) return const [];
    return e.whereType<Map<String, dynamic>>().toList();
  }

  /// users マップから自分の user_id をハンドルで引く
  static String? _resolveSelfId(Map<String, dynamic> users, String? handle) {
    if (handle == null) return null;
    final want = handle.replaceFirst('@', '').toLowerCase();
    for (final entry in users.entries) {
      final u = entry.value;
      if (u is! Map<String, dynamic>) continue;
      final screen = (u['screen_name'] as String?)?.toLowerCase();
      if (screen == want) return entry.key;
    }
    return null;
  }

  static List<DmMessage> _parseMessages(
    Map<String, dynamic> payload,
    Map<String, dynamic> users,
    String? selfId,
  ) {
    final out = <DmMessage>[];
    for (final e in _entriesOf(payload)) {
      // message 以外（リアクション・参加/退出・名前変更など）は出さない
      final message = e['message'];
      if (message is! Map<String, dynamic>) continue;
      final data = message['message_data'];
      if (data is! Map<String, dynamic>) continue;

      final senderId = data['sender_id'] as String? ?? '';
      final sender = users[senderId];
      final senderMap =
          sender is Map<String, dynamic> ? sender : const <String, dynamic>{};

      final (media, label) = _attachmentOf(data);
      out.add(DmMessage(
        id: data['id'] as String? ?? message['id'] as String? ?? '',
        senderId: senderId,
        senderName: senderMap['name'] as String? ??
            senderMap['screen_name'] as String?,
        senderAvatarUrl: senderMap['profile_image_url_https'] as String?,
        text: _expandText(data),
        sentAt: _epochMs(data['time'] ?? message['time']),
        isMine: selfId != null && senderId == selfId,
        mediaUrl: media,
        attachmentLabel: label,
      ));
    }
    return out;
  }

  /// t.co 短縮を entities.urls で元の URL に戻す。
  /// 添付（画像等）の t.co はメディアとして別枠で出すので本文から消す
  static String _expandText(Map<String, dynamic> data) {
    var text = data['text'] as String? ?? '';
    final entities = data['entities'];
    if (entities is Map<String, dynamic>) {
      final urls = entities['urls'];
      if (urls is List) {
        for (final u in urls.whereType<Map<String, dynamic>>()) {
          final short = u['url'] as String?;
          final expanded = u['expanded_url'] as String?;
          if (short != null && expanded != null) {
            text = text.replaceAll(short, expanded);
          }
        }
      }
    }
    final attachment = data['attachment'];
    if (attachment is Map<String, dynamic>) {
      for (final kind in const ['photo', 'video', 'animated_gif']) {
        final media = attachment[kind];
        if (media is Map<String, dynamic>) {
          final short = media['url'] as String?;
          if (short != null) text = text.replaceAll(short, '');
        }
      }
    }
    return text.trim();
  }

  static (String?, String?) _attachmentOf(Map<String, dynamic> data) {
    final attachment = data['attachment'];
    if (attachment is! Map<String, dynamic>) return (null, null);
    for (final (kind, label) in const [
      ('photo', '画像'),
      ('video', '動画'),
      ('animated_gif', 'GIF'),
    ]) {
      final media = attachment[kind];
      if (media is Map<String, dynamic>) {
        return (media['media_url_https'] as String?, label);
      }
    }
    if (attachment['tweet'] is Map<String, dynamic>) return (null, 'ポスト');
    if (attachment['card'] is Map<String, dynamic>) return (null, 'リンク');
    return (null, null);
  }

  static DmConversation _parseConversation(
    String id,
    Map<String, dynamic> c,
    Map<String, dynamic> users,
    String? selfId,
    DmMessage? latest,
  ) {
    final isGroup = c['type'] == 'GROUP_DM';

    // 自分以外の参加者
    final members = <DmMember>[];
    final participants = c['participants'];
    if (participants is List) {
      for (final p in participants.whereType<Map<String, dynamic>>()) {
        final uid = '${p['user_id']}';
        if (uid == selfId) continue;
        final u = users[uid];
        final uMap = u is Map<String, dynamic> ? u : const <String, dynamic>{};
        members.add(DmMember(
          id: uid,
          handle: uMap['screen_name'] as String?,
          displayName: uMap['name'] as String?,
          avatarUrl: uMap['profile_image_url_https'] as String?,
        ));
      }
    }

    // 未読: 自分の last_read_event_id が会話の先頭イベントより古いか
    var hasUnread = false;
    final sortEventId = _asId(c['sort_event_id']);
    if (participants is List && sortEventId != null && selfId != null) {
      for (final p in participants.whereType<Map<String, dynamic>>()) {
        if ('${p['user_id']}' != selfId) continue;
        final lastRead = _asId(p['last_read_event_id']) ?? 0;
        hasUnread = lastRead < sortEventId;
      }
    }

    final groupName = c['name'] as String?;
    return DmConversation(
      id: id,
      title: groupName?.isNotEmpty == true
          ? groupName!
          : members.map((m) => m.label).join('、'),
      avatarUrl: (c['avatar_image_https'] as String?) ??
          (members.isNotEmpty ? members.first.avatarUrl : null),
      isGroup: isGroup,
      hasUnread: hasUnread,
      lastText: latest == null
          ? ''
          : (latest.text.isNotEmpty
              ? latest.text
              : (latest.attachmentLabel ?? '')),
      lastAt: latest?.sentAt ?? _epochMs(c['sort_timestamp']),
      isRequest: c['trusted'] == false,
      muted: c['muted'] == true,
      members: members,
    );
  }

  /// 受信箱の続きを読むための max_id。AT_END なら null
  static String? _timelineCursor(Map<String, dynamic> payload, String name) {
    final timelines = payload['inbox_timelines'];
    if (timelines is! Map<String, dynamic>) return null;
    final t = timelines[name];
    if (t is! Map<String, dynamic>) return null;
    if (t['status'] == 'AT_END') return null;
    return t['min_entry_id'] as String?;
  }

  static DateTime? _epochMs(Object? v) {
    final ms = _asId(v);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static int? _asId(Object? v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }
}

class XDmInboxPage {
  const XDmInboxPage({
    required this.conversations,
    this.trustedNextMaxId,
    this.untrustedNextMaxId,
    this.nextMaxId,
    this.selfUserId,
  });

  /// 新しい順
  final List<DmConversation> conversations;

  /// 受信箱の続きを読む max_id。null なら終端
  final String? trustedNextMaxId;
  final String? untrustedNextMaxId;

  /// 続きページ（inbox_timeline）のさらに続き。null なら終端
  final String? nextMaxId;

  /// users マップから解決できた自分の user_id
  final String? selfUserId;
}

class XDmThreadPage {
  const XDmThreadPage({required this.messages, this.nextMaxId});

  /// 新しい順
  final List<DmMessage> messages;

  /// これより前を読む max_id。null なら終端
  final String? nextMaxId;
}
