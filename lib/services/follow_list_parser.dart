import 'dart:convert';

import '../models/follow_user.dart';

/// Following / Followers の GraphQL レスポンスを解析する純粋関数群
///
/// Follow-Capture-Tool (extract.js) の抽出ロジックを移植したもの。
/// 抽出項目を増やしたいときは [FollowUser.fromUserResult] 側だけ触れば済む。
class FollowListParser {
  FollowListParser._();

  /// 全件取得が完了したことを示すカーソル
  /// X は末尾に到達すると "0|..." を返す
  static bool isTerminalCursor(String? cursor) =>
      cursor != null && cursor.startsWith('0|');

  /// GraphQL URL の `variables` の cursor だけを差し替える。
  ///
  /// `Uri.replace` や `searchParams.set` を使うと `variables` と `features` の
  /// 並び順が崩れて X が 404 を返すことがあるため、値の部分だけを正規表現で
  /// 置換して URL の形を完全に保つ。
  static String replaceCursorInUrl(String url, String cursor) {
    final match = RegExp(r'([?&])variables=([^&]*)').firstMatch(url);
    if (match == null) return url;
    try {
      final vars = json.decode(Uri.decodeComponent(match.group(2)!))
          as Map<String, dynamic>;
      vars['cursor'] = cursor;
      final encoded = Uri.encodeComponent(json.encode(vars));
      return url.replaceRange(
          match.start, match.end, '${match.group(1)}variables=$encoded');
    } catch (_) {
      return url;
    }
  }

  /// レスポンス全体から users と次ページの cursor を取り出す。
  ///
  /// [skipped] は「ユーザーのエントリなのに取り出せなかった件数」。
  /// 黙って落とすと取りこぼしに気づけないので数えて返す。
  static ({List<FollowUser> users, String? cursor, int skipped}) parse(
      Map<String, dynamic> body) {
    final instructions = _instructions(body);
    final extracted = _extractUsers(instructions);
    return (
      users: extracted.users,
      cursor: _extractBottomCursor(instructions),
      skipped: extracted.skipped,
    );
  }

  /// 最初のユーザーの項目がどこに入っているかを 1 行で返す (診断用)。
  /// X が legacy から新形式へ移行途中なので、取りこぼしの切り分けに使う。
  static String describeFirstUser(Map<String, dynamic> body) {
    for (final ins in _instructions(body).map(_asMap)) {
      final entries = ins['entries'];
      if (entries is! List) continue;
      for (final entry in entries) {
        final content = _asMap(_asMap(entry)['content']);
        final result =
            _asMap(_asMap(content['itemContent'])['user_results'])['result'];
        if (result is! Map<String, dynamic>) continue;
        final legacy = _asMap(result['legacy']);
        final parsed = FollowUser.fromUserResult(result);
        // legacy が空でも件数が取れているかを、この 1 行で切り分ける
        // relationship_perspectives は「閲覧アカウントから見た関係」。
        // 一覧に blocked_by / blocking が載るなら、つながっている人のフォロー先を
        // 走査してブロック状態を集められる。載らないなら 1 人ずつ引く必要がある。
        // 中身が見えないと設計が決まらないので、そのまま出す。
        return 'top=[${result.keys.join(",")}] '
            'legacy=[${legacy.keys.take(20).join(",")}] '
            'relationship_counts=${_asMap(result['relationship_counts'])} '
            'relationship_perspectives=${_asMap(result['relationship_perspectives'])} '
            'tweet_counts=${_asMap(result['tweet_counts'])} '
            'parsed=(followers=${parsed?.followersCount} '
            'friends=${parsed?.friendsCount} statuses=${parsed?.statusesCount})';
      }
    }
    return '(ユーザーが見つからない)';
  }

  /// timeline instructions を取り出す。
  /// X は A/B で `timeline` / `timeline_v2` を出し分けるため両方見る。
  static List<Object?> _instructions(Map<String, dynamic> body) {
    final result = _asMap(_asMap(_asMap(body['data'])['user'])['result']);
    for (final key in const ['timeline', 'timeline_v2']) {
      final container = _asMap(result[key]);
      // timeline.timeline.instructions が通常形、timeline.instructions は簡略形
      for (final inner in [_asMap(container['timeline']), container]) {
        final ins = inner['instructions'];
        if (ins is List && ins.isNotEmpty) return ins;
      }
    }
    return const [];
  }

  /// エントリからユーザーを取り出す。
  ///
  /// [skipped] は「ユーザーのエントリなのに解析できなかった件数」。
  /// 黙って捨てると取りこぼしに気づけないので数える。
  static ({List<FollowUser> users, int skipped}) _extractUsers(
      List<Object?> instructions) {
    final users = <FollowUser>[];
    var skipped = 0;

    for (final ins in instructions.map(_asMap)) {
      if (ins['type'] != 'TimelineAddEntries') continue;
      final entries = ins['entries'];
      if (entries is! List) continue;

      for (final entry in entries) {
        final content = _asMap(_asMap(entry)['content']);
        final result =
            _asMap(_asMap(content['itemContent'])['user_results'])['result'];
        if (result is! Map<String, dynamic>) continue;

        final user = FollowUser.fromUserResult(result);
        if (user != null) {
          users.add(user);
        } else {
          skipped++;
        }
      }
    }
    return (users: users, skipped: skipped);
  }

  /// Bottom カーソルは TimelineAddEntries 以外の instruction にも現れるため
  /// 全 instruction を走査する
  static String? _extractBottomCursor(List<Object?> instructions) {
    for (final ins in instructions.map(_asMap)) {
      final entries = ins['entries'];
      if (entries is! List) continue;
      for (final entry in entries) {
        final content = _asMap(_asMap(entry)['content']);
        if (content['cursorType'] == 'Bottom') {
          final value = content['value'];
          if (value is String && value.isNotEmpty) return value;
        }
      }
    }
    return null;
  }
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

/// 走査の相手がいまどういう状態か
enum FollowTargetAvailability {
  /// 一覧を読める
  available,

  /// 非公開で、実行アカウントがフォローしていない
  protected,

  /// 凍結されている
  suspended,

  /// アカウントが無い（削除・ID 変更）
  missing,

  /// X が「見られない」と言っているが理由が上のどれでもない
  unavailable;

  bool get readable => this == available;

  /// 調査の記録や知らせに出す短い言い方
  String get label => switch (this) {
        available => '読める',
        protected => '非公開',
        suspended => '凍結',
        missing => '存在しない',
        unavailable => '見られない',
      };
}

/// UserByScreenName の応答から読んだ、相手の状態。
///
/// 一覧ページを開くと X 自身が先に UserByScreenName を投げる。鍵・凍結・
/// 削除済みだとフォロー一覧の通信は飛ばないので、ここを見ないと
/// 捕獲のタイムアウトまで待つしかなくなる。
class FollowTargetState {
  const FollowTargetState({
    required this.screenName,
    required this.availability,
    this.message,
  });

  /// 問い合わせた @ID（小文字）。応答が空でも URL から分かる
  final String screenName;
  final FollowTargetAvailability availability;

  /// X が添えた理由の文（UserUnavailable の message）
  final String? message;

  bool get readable => availability.readable;

  /// GraphQL の URL と応答本文から状態を読む。
  ///
  /// 応答が UserByScreenName の形をしていなければ null。
  /// 「分からない」を「読める」に倒さないため、判断できない形は null で返し、
  /// 呼び出し側は何もしない（これまでどおり捕獲を待つ）。
  static FollowTargetState? parse(String url, String body) {
    final fromUrl = _screenNameFromUrl(url);
    final Object? decoded;
    try {
      decoded = json.decode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) return null;

    final result = _asMap(
        _asMap(data['user'])['result']);

    // 削除済み・存在しない ID は data が空で返る
    if (result.isEmpty) {
      if (fromUrl == null) return null;
      return FollowTargetState(
          screenName: fromUrl, availability: FollowTargetAvailability.missing);
    }

    final legacy = _asMap(result['legacy']);
    final core = _asMap(result['core']);
    final screenName = fromUrl ??
        (legacy['screen_name'] ?? core['screen_name'])
            ?.toString()
            .toLowerCase();
    if (screenName == null) return null;

    if (result['__typename'] == 'UserUnavailable') {
      final reason = result['reason']?.toString() ?? '';
      final message = result['message']?.toString();
      return FollowTargetState(
        screenName: screenName,
        availability: reason.toLowerCase() == 'suspended'
            ? FollowTargetAvailability.suspended
            : FollowTargetAvailability.unavailable,
        message: message,
      );
    }

    // X は legacy から privacy / relationship_perspectives へ移している最中。
    // 両方を見る（FollowUser.fromUserResult と同じ）
    final privacy = _asMap(result['privacy']);
    final perspectives =
        _asMap(result['relationship_perspectives']);
    final isProtected =
        (legacy['protected'] ?? privacy['protected']) == true;
    final following =
        (legacy['following'] ?? perspectives['following']) == true;
    return FollowTargetState(
      screenName: screenName,
      availability: isProtected && !following
          ? FollowTargetAvailability.protected
          : FollowTargetAvailability.available,
    );
  }

  /// URL の variables から screen_name を読む（小文字）
  static String? _screenNameFromUrl(String url) {
    final match = RegExp(r'[?&]variables=([^&]*)').firstMatch(url);
    if (match == null) return null;
    try {
      final vars = json.decode(Uri.decodeComponent(match.group(1)!));
      if (vars is! Map) return null;
      final name = vars['screen_name'];
      return name is String && name.isNotEmpty ? name.toLowerCase() : null;
    } catch (_) {
      return null;
    }
  }
}
