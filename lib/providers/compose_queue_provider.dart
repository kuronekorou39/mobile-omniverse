import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/x_webview_action_service.dart';
import 'activity_log_provider.dart';

enum PostJobStatus { pending, posting, success, failure }

class PostJob {
  PostJob({
    required this.id,
    required this.text,
    required this.account,
    this.inReplyToPost,
    this.quotedPost,
    this.status = PostJobStatus.pending,
    this.errorMessage,
    this.statusCode,
  });

  final String id;
  final String text;
  final Account account;
  final Post? inReplyToPost;
  final Post? quotedPost;
  final PostJobStatus status;
  final String? errorMessage;
  final int? statusCode;

  PostJob copyWith({
    PostJobStatus? status,
    String? errorMessage,
    int? statusCode,
  }) {
    return PostJob(
      id: id,
      text: text,
      account: account,
      inReplyToPost: inReplyToPost,
      quotedPost: quotedPost,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      statusCode: statusCode ?? this.statusCode,
    );
  }
}

class ComposeQueueState {
  const ComposeQueueState({this.jobs = const []});

  final List<PostJob> jobs;

  bool get hasJobs => jobs.isNotEmpty;
  int get totalCount => jobs.length;
  int get successCount =>
      jobs.where((j) => j.status == PostJobStatus.success).length;
  int get failureCount =>
      jobs.where((j) => j.status == PostJobStatus.failure).length;
  int get completedCount => successCount + failureCount;
  bool get isAllDone => totalCount > 0 && completedCount == totalCount;
  bool get hasFailure => failureCount > 0;

  PostJob? get currentlyPosting {
    for (final j in jobs) {
      if (j.status == PostJobStatus.posting) return j;
    }
    return null;
  }
}

class ComposeQueueNotifier extends StateNotifier<ComposeQueueState> {
  ComposeQueueNotifier(this._ref) : super(const ComposeQueueState());

  final Ref _ref;
  bool _running = false;

  /// 投稿をキューに追加（複数アカウント対応のため accounts はリスト）
  void enqueue({
    required String text,
    required List<Account> accounts,
    Post? inReplyToPost,
    Post? quotedPost,
  }) {
    final base = DateTime.now().microsecondsSinceEpoch;
    final newJobs = [
      for (var i = 0; i < accounts.length; i++)
        PostJob(
          id: '${base}_${accounts[i].id}_$i',
          text: text,
          account: accounts[i],
          inReplyToPost: inReplyToPost,
          quotedPost: quotedPost,
        ),
    ];
    state = ComposeQueueState(jobs: [...state.jobs, ...newJobs]);
    unawaited(_process());
  }

  /// バナーを引っ込める（全完了後にユーザーが閉じる、自動 dismiss）
  void dismiss() {
    state = const ComposeQueueState();
  }

  Future<void> _process() async {
    if (_running) return;
    _running = true;

    try {
      while (true) {
        PostJob? job;
        for (final j in state.jobs) {
          if (j.status == PostJobStatus.pending) {
            job = j;
            break;
          }
        }
        if (job == null) break;

        _updateJob(job.id, status: PostJobStatus.posting);

        try {
          if (job.account.service == SnsService.x) {
            await _postToX(job);
          } else {
            await _postToBluesky(job);
          }
        } catch (e) {
          _updateJob(job.id,
              status: PostJobStatus.failure, errorMessage: 'エラー: $e');
          _ref.read(activityLogProvider.notifier).logAction(
                action: ActivityAction.post,
                platform: job.account.service,
                accountHandle: job.account.handle,
                accountId: job.account.id,
                targetSummary: _summary(job.text),
                success: false,
                errorMessage: '$e',
              );
        }

        // 連続投稿時の bot 検知回避＋ UI のチカチカ抑制
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _postToX(PostJob job) async {
    String? attachmentUrl;
    String? inReplyToId;
    if (job.quotedPost != null && job.quotedPost!.permalink != null) {
      attachmentUrl = job.quotedPost!.permalink;
    }
    if (job.inReplyToPost != null) {
      inReplyToId = job.inReplyToPost!.id.replaceFirst('x_', '');
    }
    final result = await XWebViewActionService.instance.createTweet(
      job.account.xCredentials,
      job.text,
      attachmentUrl: attachmentUrl,
      inReplyToId: inReplyToId,
    );
    _updateJob(job.id,
        status: result.success ? PostJobStatus.success : PostJobStatus.failure,
        statusCode: result.statusCode,
        errorMessage: result.success
            ? null
            : 'X 投稿失敗 (${result.statusCode})');
    final body = result.body;
    _ref.read(activityLogProvider.notifier).logAction(
          action: ActivityAction.post,
          platform: SnsService.x,
          accountHandle: job.account.handle,
          accountId: job.account.id,
          targetSummary: _summary(job.text),
          success: result.success,
          statusCode: result.statusCode,
          responseSnippet:
              '[WebView] ${body.length > 500 ? '${body.substring(0, 500)}...' : body}',
        );
  }

  Future<void> _postToBluesky(PostJob job) async {
    String? quoteUri;
    String? quoteCid;
    if (job.quotedPost != null) {
      quoteUri = job.quotedPost!.uri;
      quoteCid = job.quotedPost!.cid;
    }
    String? replyUri;
    String? replyCid;
    if (job.inReplyToPost != null) {
      replyUri = job.inReplyToPost!.uri;
      replyCid = job.inReplyToPost!.cid;
    }
    final ok = await BlueskyApiService.instance.createPost(
      job.account.blueskyCredentials,
      job.text,
      quoteUri: quoteUri,
      quoteCid: quoteCid,
      replyUri: replyUri,
      replyCid: replyCid,
    );
    _updateJob(job.id,
        status: ok ? PostJobStatus.success : PostJobStatus.failure,
        errorMessage: ok ? null : 'Bluesky 投稿失敗');
    _ref.read(activityLogProvider.notifier).logAction(
          action: ActivityAction.post,
          platform: SnsService.bluesky,
          accountHandle: job.account.handle,
          accountId: job.account.id,
          targetSummary: _summary(job.text),
          success: ok,
        );
  }

  void _updateJob(
    String id, {
    PostJobStatus? status,
    int? statusCode,
    String? errorMessage,
  }) {
    final newJobs = state.jobs
        .map((j) => j.id == id
            ? j.copyWith(
                status: status,
                statusCode: statusCode,
                errorMessage: errorMessage,
              )
            : j)
        .toList();
    state = ComposeQueueState(jobs: newJobs);
  }

  String _summary(String text) =>
      text.length > 40 ? '${text.substring(0, 40)}…' : text;
}

final composeQueueProvider =
    StateNotifierProvider<ComposeQueueNotifier, ComposeQueueState>(
  (ref) => ComposeQueueNotifier(ref),
);
