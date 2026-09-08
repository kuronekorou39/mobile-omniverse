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
///   2  リクエスト UUID
///   3  送信者のユーザー ID
///   4  会話 ID（`自分:相手` の形）
///   5  権限を表す JWT（本文ではない）
///   6  送信時刻（ミリ秒）
///   7 → (種類ごとの番号) → 100  ペイロード。**さらに入れ子の Thrift**
///       で、その中の 1 → 1 → 1 が本文。7 の直下の番号はイベントの種類で
///       変わる（実測で 1 / 3 / 12）ので決め打ちしない
///   9  暗号化の鍵交換（ECDSA P-256 の公開鍵など。本文ではない）
class XChatParser {
  XChatParser._();

  // ─── フィールド番号 ───
  static const _fMessageId = 1;
  static const _fSenderId = 3;
  static const _fSentAt = 6;
  static const _fPayload = 7;
  static const _fBody = 100;

  /// 本文までの道のり。100 の中身を Thrift として読み直したあと、
  /// この順にたどる
  static const _bodyPath = [1, 1, 1];

  /// 7 の直下がこれだけなら、吹き出しにしない内部イベント。
  /// 12 は既読の位置更新で、中身は数値だけ
  static const _systemEventKinds = {12, 3};

  /// 暗号化された本文が入る枝。108.1 が 32 バイトの鍵、108.2 が暗号文で、
  /// XChat の end-to-end 暗号にあたる。鍵は端末側にあり復号できない
  static const _fEncrypted = 108;

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

  /// メッセージ 1 件。ID・送信者・時刻が欠けていれば null
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

    // ID・送信者・時刻がそろっていればメッセージとみなす。本文が読めな
    // かったからといって落とすと、やり取りの数も時系列も狂う
    if (id == null || senderId.isEmpty || sentAt == null) return null;

    // 7 の直下の番号はイベントの種類。12 は既読などの内部イベントで、
    // 中身は数値だけ。吹き出しとして出すものではない
    final payloadKinds = root[_fPayload];
    if (payloadKinds is Map<int, dynamic> &&
        payloadKinds.keys.every((k) => _systemEventKinds.contains(k))) {
      return null;
    }

    // 本文は 7 → (種類ごとの番号) → 100 のバイト列を、もう一度 Thrift と
    // して読み直した先にある。7 の下の番号はイベントの種類で変わる
    // （1 のことも 12 のこともある）ので、決め打ちせず全部見る
    String? text;
    String? mediaUrl;
    var encrypted = false;
    final payload = root[_fPayload];
    if (payload is Map<int, dynamic>) {
      for (final v in payload.values) {
        final inner = v is Map<int, dynamic> ? v : ThriftReader.asStruct(v);
        if (inner == null) continue;
        if (inner[_fEncrypted] != null) encrypted = true;
        final body = ThriftReader.asStruct(inner[_fBody]);
        if (body == null) continue;
        mediaUrl ??= _findUrl(body);
        // 添付のときは同じ枝にファイル名が入っている。本文と取り違えると
        // 「i9ica_Q9.jpg」のような文字列が吹き出しに出る
        if (mediaUrl == null) text ??= _textOf(body);
      }
    }

    final hasText = text != null && text.isNotEmpty;
    // 復号できないものを「添付」と書くと、画像が来たように見えて紛らわしい
    final attachmentLabel = hasText
        ? null
        : (mediaUrl != null
            ? '画像'
            : (encrypted ? '暗号化されたメッセージ' : '不明な形式'));

    return DmMessage(
      id: id,
      senderId: senderId,
      text: text ?? '',
      sentAt: sentAt,
      isMine: selfUserId != null && senderId == selfUserId,
      mediaUrl: mediaUrl,
      attachmentLabel: attachmentLabel,
    );
  }

  /// ペイロードから本文を取り出す。
  ///
  /// 実測では 1 → 1 → 1 に入っているが、種類によって階層が違うことが
  /// あるので、見つからなければ中を探しに行く
  static String? _textOf(Map<int, dynamic> body) {
    Object? node = body;
    for (final fid in _bodyPath) {
      if (node is! Map<int, dynamic>) {
        node = null;
        break;
      }
      final next = node[fid];
      final asText = ThriftReader.asText(next);
      if (fid == _bodyPath.last && _looksLikeBody(asText)) return asText;
      node = next is Map<int, dynamic> ? next : ThriftReader.asStruct(next);
    }
    return _searchText(body);
  }

  /// 本文らしい文字列を探す。ID・URL・JWT は本文ではない
  static String? _searchText(Map<int, dynamic> node, {int depth = 0}) {
    if (depth > 6) return null;
    for (final v in node.values) {
      final s = ThriftReader.asText(v);
      if (_looksLikeBody(s)) return s;
      final sub = v is Map<int, dynamic> ? v : ThriftReader.asStruct(v);
      if (sub != null) {
        final found = _searchText(sub, depth: depth + 1);
        if (found != null) return found;
      } else if (v is List) {
        for (final e in v) {
          final m = e is Map<int, dynamic> ? e : ThriftReader.asStruct(e);
          if (m == null) continue;
          final found = _searchText(m, depth: depth + 1);
          if (found != null) return found;
        }
      }
    }
    return null;
  }

  static bool _looksLikeBody(String? s) {
    if (s == null || s.isEmpty) return false;
    // 権限トークン。画面に出すと base64 の羅列に見える
    if (s.startsWith('eyJ')) return false;
    if (s.startsWith('http')) return false;
    // ID や時刻
    if (RegExp(r'^\d+$').hasMatch(s)) return false;
    if (RegExp(r'^\d+:\d+$').hasMatch(s)) return false;
    if (RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(s)) return false;
    return true;
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
