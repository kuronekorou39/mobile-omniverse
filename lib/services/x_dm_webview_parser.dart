import '../models/dm_models.dart';

/// WebView の DOM から拾った DM を、画面用のモデルにならす。
///
/// XChat のメッセージは API 越しだと暗号化されていて復号できないが、
/// ブラウザでは復号済みの本文が DOM に出ている。そこから読むので、
/// 暗号化された会話も普通に読める。
///
/// 時刻は画面の表示そのまま（"8:06 PM" や "1w"）で、正確な日時は
/// 取れない。並び順は DOM の並び（古い順）を信じる。
class XDmWebViewParser {
  XDmWebViewParser._();

  /// 会話一覧
  static List<DmConversation> parseInbox(List<Map<String, dynamic>> rows) {
    final convos = <DmConversation>[];
    for (final r in rows) {
      final id = r['id'];
      if (id is! String || id.isEmpty) continue;
      final title = (r['title'] as String?)?.trim() ?? '';
      convos.add(DmConversation(
        id: id,
        title: title,
        isGroup: false,
        hasUnread: false,
        lastText: (r['last'] as String?)?.trim() ?? '',
        // 一覧の時刻は "1w" のような相対表記。日時には直せないので持たない
        lastAt: null,
        members: _membersOf(id, title),
      ));
    }
    return convos;
  }

  /// スレッド。画面と同じく古い順で並んでいるので、新しい順に直す
  static List<DmMessage> parseConversation(
    List<Map<String, dynamic>> rows, {
    String? selfUserId,
  }) {
    final messages = <DmMessage>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final text = (r['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;
      final mine = r['mine'] == true;
      messages.add(DmMessage(
        id: (r['id'] as String?) ?? 'dom-$i',
        // DOM からは送信者 ID が取れない。左右の寄りだけが手がかり
        senderId: mine ? (selfUserId ?? 'me') : '',
        text: text,
        sentAt: null,
        isMine: mine,
      ));
    }
    return messages.reversed.toList();
  }

  /// 会話 ID は `自分:相手` の形。相手側だけを取り出す
  static List<DmMember> _membersOf(String conversationId, String title) {
    final parts = conversationId.split(':');
    if (parts.length != 2) return const [];
    return [
      DmMember(id: parts.last, displayName: title.isEmpty ? null : title),
    ];
  }
}
