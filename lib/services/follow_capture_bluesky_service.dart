import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/follow_user.dart';
import 'account_storage_service.dart';
import 'bluesky_api_service.dart';
import 'debug_log_service.dart';
import 'follow_capture_engine.dart';

/// Bluesky のフォロー/フォロワー一覧を取る口。
///
/// X は x-client-transaction-id の検証があるため実表示の WebView が要るが
/// ([FollowCaptureWebViewService])、Bluesky は素の HTTP で取れる。
/// [FollowCaptureEngine] から見える形は同じなので、対象の SNS で
/// このクラスと WebView 版を差し替えるだけで済む。
///
/// 一覧の API が返す profileView にはフォロワー数・フォロー数・投稿数が
/// 入っていない。件数が無いと「件数の変化」も並び替えも成り立たないので、
/// 1 ページ取るたびに getProfiles で 25 人ずつ引き直して補う。
class FollowCaptureBlueskyService {
  FollowCaptureBlueskyService._();
  static final instance = FollowCaptureBlueskyService._();

  @visibleForTesting
  BlueskyApiService? apiOverride;

  BlueskyApiService get _api => apiOverride ?? BlueskyApiService.instance;

  /// リフレッシュで差し替わった資格情報。
  ///
  /// エンジンは同じ [Account] を毎回渡してくるので、更新後もそれを使うと
  /// 期限切れのトークンを送り続けることになる。ここで持ち替える。
  final _refreshed = <String, BlueskyCredentials>{};

  /// 走査の区切りで呼ぶ。次の走査に古い資格情報を持ち越さない
  void reset() => _refreshed.clear();

  BlueskyCredentials _credsFor(Account account) =>
      _refreshed[account.id] ?? account.blueskyCredentials;

  Future<BlueskyCredentials> _refresh(Account account) async {
    final next = await _api.refreshSession(_credsFor(account));
    _refreshed[account.id] = next;
    await AccountStorageService.instance
        .updateAccount(account.copyWith(credentials: next));
    _log('トークンを更新しました (${account.handle})');
    return next;
  }

  /// 1 ページ取得する。[FollowPageFetcher] として [FollowCaptureEngine] に渡す。
  Future<FollowListPage> fetchPage({
    required Account account,
    required String targetHandle,
    required FollowListKind kind,
    String? cursor,
    CaptureCancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final followers = kind == FollowListKind.followers;

    var page = await _api.getFollowList(
      _credsFor(account),
      targetHandle,
      followers: followers,
      cursor: cursor,
    );

    // 期限切れは 1 回だけ取り直して再試行する。
    // ここで諦めるとエンジンがアカウントをプールから外してしまう
    if (page.statusCode == 401) {
      _log('401 → トークンを更新して再試行');
      try {
        final creds = await _refresh(account);
        cancelToken?.throwIfCancelled();
        page = await _api.getFollowList(
          creds,
          targetHandle,
          followers: followers,
          cursor: cursor,
        );
      } on BlueskyAuthException catch (e) {
        _log('トークンの更新に失敗: $e');
        return const FollowListPage(statusCode: 401);
      }
    }

    if (page.statusCode != 200) {
      return FollowListPage(statusCode: page.statusCode);
    }

    final users = await _withCounts(account, page.users, cancelToken);
    return FollowListPage(
      statusCode: 200,
      users: users,
      cursor: page.cursor,
    );
  }

  /// 件数を getProfiles で補う。
  ///
  /// 補えなかった相手は一覧で得た値 (0) のまま残す。ここで例外にすると
  /// ページごと落ちて cursor が進まなくなるので、取れた分だけ載せる。
  Future<List<FollowUser>> _withCounts(
    Account account,
    List<FollowUser> users,
    CaptureCancelToken? cancelToken,
  ) async {
    if (users.isEmpty) return users;

    final detailed = <String, FollowUser>{};
    const batchSize = BlueskyApiService.profilesBatchSize;

    for (var i = 0; i < users.length; i += batchSize) {
      cancelToken?.throwIfCancelled();
      final batch = users.skip(i).take(batchSize).toList();
      try {
        detailed.addAll(await _api.getProfiles(
          _credsFor(account),
          batch.map((u) => u.restId).toList(),
        ));
      } on BlueskyAuthException {
        try {
          final creds = await _refresh(account);
          detailed.addAll(await _api.getProfiles(
            creds,
            batch.map((u) => u.restId).toList(),
          ));
        } catch (e) {
          _log('件数の補完に失敗 (更新後も): $e');
        }
      } catch (e) {
        _log('件数の補完に失敗: $e');
      }
    }

    return [
      for (final u in users)
        detailed[u.restId] == null ? u : u.withCountsFrom(detailed[u.restId]!),
    ];
  }

  static void _log(String message) {
    debugPrint('[FollowCaptureBluesky] $message');
    DebugLogService.instance.log('FollowCaptureBluesky', message);
  }
}
