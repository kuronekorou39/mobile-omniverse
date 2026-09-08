import 'dart:typed_data';

import '../models/dm_models.dart';
import 'thrift_reader.dart';

/// XChat（X の新しい DM）の応答を画面用のモデルにならす。
///
/// 1.1 の dm/*.json には移行前のメッセージしか残っていない。こちらが
/// 現行の経路。メッセージは Base64 の Thrift で届き、フィールド番号の
/// 対応は実機の応答から割り出した:
///
///   1  メッセージ ID
///   2  直前のメッセージ ID（並びの前後関係）
///   3  送信者のユーザー ID
///   4  会話 ID（`自分:相手` の形）
///   6  送信時刻（ミリ秒）
///   7 → 1 → 100  本文。テキストならそのまま、添付なら入れ子の Thrift
class XChatParser {
  XChatParser._();

  // ─── フィールド番号 ───
  static const _fMessageId = 1;
  static const _fSenderId = 3;
  static const _fSentAt = 6;
  static const _fPayload = 7;
  static const _fPayloadInner = 1;
  static const _fBody = 100;

  /// 添付の入れ子に入っている、表示に使える URL
  static const _fAttachmentUrl = 8;

  /// 会話一覧
  static List<DmConversation> parseInbox(
    Map<String, dynamic> data, {
    String? selfUserId,
  }) {
    final page = data['get_initial_chat_page'];
    if (page is! Map<String, dynamic>) return const [];
    final items = page['items'];
    if (items is! List) return const [];

    final convos = <DmConversation>[];
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final detail = item['conversation_detail'];
      if (detail is! Map<String, dynamic>) continue;
      final id = detail['conversation_id'];
      if (id is! String || id.isEmpty) continue;

      final members = _membersOf(detail, selfUserId);
      final latest = _latestMessage(item, selfUserId);

      convos.add(DmConversation(
        id: id,
        title: members.map((m) => m.label).join('、'),
        avatarUrl: members.isNotEmpty ? members.first.avatarUrl : null,
        isGroup: members.length > 1,
        hasUnread: false,
        lastText: latest?.text ?? '',
        lastAt: latest?.sentAt,
        muted: detail['is_muted'] == true,
        members: members,
      ));
    }
    convos.sort((a, b) {
      final at = a.lastAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.lastAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return convos;
  }

  /// スレッド。新しい順で返す
  static List<DmMessage> parseConversation(
    Map<String, dynamic> data, {
    String? selfUserId,
  }) {
    final page = data['get_conversation_page'];
    if (page is! Map<String, dynamic>) return const [];
    final events = page['encoded_message_events'];
    if (events is! List) return const [];

    final messages = <DmMessage>[];
    for (final e in events.whereType<String>()) {
      final m = parseEvent(e, selfUserId: selfUserId);
      if (m != null) messages.add(m);
    }
    messages.sort((a, b) {
      final at = a.sentAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.sentAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return messages;
  }

  /// メッセージ 1 件。本文も添付も無ければ null（参加・既読などのイベント）
  static DmMessage? parseEvent(String base64Event, {String? selfUserId}) {
    Map<int, dynamic> root;
    try {
      root = ThriftReader.fromBase64(base64Event).readStruct();
    } catch (_) {
      return null;
    }

    final id = ThriftReader.asText(root[_fMessageId]);
    final senderId = ThriftReader.asText(root[_fSenderId]) ?? '';
    final sentAtRaw = ThriftReader.asText(root[_fSentAt]);
    final sentAt = _toDate(sentAtRaw);

    final payload = root[_fPayload];
    if (payload is! Map<int, dynamic>) return null;
    final inner = payload[_fPayloadInner];
    if (inner is! Map<int, dynamic>) return null;

    final body = inner[_fBody];
    if (body == null) return null;

    // 本文はテキストのことも、添付を表す入れ子の Thrift のこともある
    final text = ThriftReader.asText(body);
    String? mediaUrl;
    String? attachmentLabel;
    if (text == null) {
      final nested = ThriftReader.asStruct(body);
      if (nested == null) return null;
      mediaUrl = _findUrl(nested);
      attachmentLabel = mediaUrl == null ? '添付' : '画像';
    }

    if ((text == null || text.isEmpty) && mediaUrl == null &&
        attachmentLabel == null) {
      return null;
    }

    return DmMessage(
      id: id ?? '',
      senderId: senderId,
      text: text ?? '',
      sentAt: sentAt,
      isMine: selfUserId != null && senderId == selfUserId,
      mediaUrl: mediaUrl,
      attachmentLabel: attachmentLabel,
    );
  }

  /// 添付の入れ子から URL を探す。階層が読めない形もあるので浅く走査する
  static String? _findUrl(Map<int, dynamic> node, {int depth = 0}) {
    if (depth > 6) return null;
    final direct = ThriftReader.asText(node[_fAttachmentUrl]);
    if (direct != null && direct.startsWith('http')) return direct;
    for (final v in node.values) {
      if (v is Map<int, dynamic>) {
        final found = _findUrl(v, depth: depth + 1);
        if (found != null) return found;
      } else if (v is List) {
        for (final e in v) {
          if (e is Map<int, dynamic>) {
            final found = _findUrl(e, depth: depth + 1);
            if (found != null) return found;
          }
        }
      } else if (v is Uint8List) {
        final s = ThriftReader.asText(v);
        if (s != null && s.startsWith('http')) return s;
      }
    }
    return null;
  }

  static List<DmMember> _membersOf(
      Map<String, dynamic> detail, String? selfUserId) {
    final results = detail['participants_results'];
    if (results is! List) return const [];
    final members = <DmMember>[];
    for (final p in results.whereType<Map<String, dynamic>>()) {
      final restId = p['rest_id'];
      if (restId is! String || restId == selfUserId) continue;
      final result = p['result'];
      final core = result is Map<String, dynamic> ? result['core'] : null;
      final avatar = result is Map<String, dynamic> ? result['avatar'] : null;
      members.add(DmMember(
        id: restId,
        handle: core is Map<String, dynamic>
            ? core['screen_name'] as String?
            : null,
        displayName:
            core is Map<String, dynamic> ? core['name'] as String? : null,
        avatarUrl: avatar is Map<String, dynamic>
            ? avatar['image_url'] as String?
            : null,
      ));
    }
    return members;
  }

  static DmMessage? _latestMessage(
      Map<String, dynamic> item, String? selfUserId) {
    final events = item['latest_message_events'];
    if (events is! List) return null;
    DmMessage? newest;
    for (final e in events.whereType<String>()) {
      final m = parseEvent(e, selfUserId: selfUserId);
      if (m == null) continue;
      if (newest == null ||
          (m.sentAt != null &&
              (newest.sentAt == null || m.sentAt!.isAfter(newest.sentAt!)))) {
        newest = m;
      }
    }
    return newest;
  }

  static DateTime? _toDate(String? millis) {
    if (millis == null) return null;
    final v = int.tryParse(millis);
    if (v == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(v);
  }
}
