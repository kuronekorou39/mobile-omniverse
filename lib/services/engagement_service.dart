import '../models/account.dart';
import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_api_service.dart';

/// いいね/RT の API 呼び出し結果
class EngagementResult {
  const EngagementResult({
    required this.success,
    this.statusCode,
    this.responseSnippet,
    this.errorMessage,
  });

  final bool success;
  final int? statusCode;
  final String? responseSnippet;
  final String? errorMessage;
}

/// いいね/RT の API 呼び出しとアクティビティログ記録を一元管理
class EngagementService {
  EngagementService._();
  static final instance = EngagementService._();

  /// いいね or いいね解除を実行
  Future<EngagementResult> like({
    required Post post,
    required Account account,
    required bool unlike,
  }) async {
    try {
      bool success = false;
      int? statusCode;
      String? responseSnippet;

      if (post.source == SnsService.x) {
        final creds = account.xCredentials;
        final tweetId = post.id.replaceFirst('x_', '');
        final result = unlike
            ? await XApiService.instance.unlikeTweetWithDetail(creds, tweetId)
            : await XApiService.instance.likeTweetWithDetail(creds, tweetId);
        success = result.success;
        statusCode = result.statusCode;
        responseSnippet = result.bodySnippet;
      } else if (post.source == SnsService.bluesky) {
        final creds = account.blueskyCredentials;
        if (unlike) {
          final likeUri = post.bskyLikeUriFor(account.id);
          if (likeUri != null) {
            success = await BlueskyApiService.instance.unlikePost(creds, likeUri);
          }
        } else {
          final postUri = post.uri;
          final postCid = post.cid;
          if (postUri != null && postCid != null && postCid.isNotEmpty) {
            final result = await BlueskyApiService.instance.likePost(creds, postUri, postCid);
            success = result != null;
          }
        }
      }

      return EngagementResult(
        success: success,
        statusCode: statusCode,
        responseSnippet: responseSnippet,
      );
    } catch (e) {
      return EngagementResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// リポスト or リポスト解除を実行
  Future<EngagementResult> repost({
    required Post post,
    required Account account,
    required bool unrepost,
  }) async {
    try {
      bool success = false;
      int? statusCode;
      String? responseSnippet;

      if (post.source == SnsService.x) {
        final creds = account.xCredentials;
        final tweetId = post.id.replaceFirst('x_', '');
        final result = unrepost
            ? await XApiService.instance.unretweetWithDetail(creds, tweetId)
            : await XApiService.instance.retweetWithDetail(creds, tweetId);
        success = result.success;
        statusCode = result.statusCode;
        responseSnippet = result.bodySnippet;
      } else if (post.source == SnsService.bluesky) {
        final creds = account.blueskyCredentials;
        if (unrepost) {
          final repostUri = post.bskyRepostUriFor(account.id);
          if (repostUri != null) {
            success = await BlueskyApiService.instance.deleteRepost(creds, repostUri);
          }
        } else {
          final postUri = post.uri;
          final postCid = post.cid;
          if (postUri != null && postCid != null && postCid.isNotEmpty) {
            final result = await BlueskyApiService.instance.repost(creds, postUri, postCid);
            success = result != null;
          }
        }
      }

      return EngagementResult(
        success: success,
        statusCode: statusCode,
        responseSnippet: responseSnippet,
      );
    } catch (e) {
      return EngagementResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// アクティビティログ用の投稿サマリーを生成
  static String postSummary(Post post) =>
      post.body.length > 40 ? '${post.body.substring(0, 40)}…' : post.body;
}
