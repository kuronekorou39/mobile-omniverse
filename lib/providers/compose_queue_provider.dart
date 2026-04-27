import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/activity_log.dart';
import '../models/post.dart';
import '../models/sns_service.dart';
import '../services/bluesky_api_service.dart';
import '../services/draft_service.dart';
import '../services/image_resize_service.dart';
import '../services/x_webview_action_service.dart';
import 'activity_log_provider.dart';
import 'draft_list_provider.dart';

enum PostJobStatus { pending, posting, success, failure }

class PostJob {
  PostJob({
    required this.id,
    required this.text,
    required this.account,
    this.inReplyToPost,
    this.quotedPost,
    this.images = const [],
    this.status = PostJobStatus.pending,
    this.errorMessage,
    this.statusCode,
  });

  final String id;
  final String text;
  final Account account;
  final Post? inReplyToPost;
  final Post? quotedPost;
  final List<XFile> images;
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
      images: images,
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
  String? _sourceDraftId;

  /// 投稿をキューに追加（複数アカウント対応のため accounts はリスト）。
  /// 既に古い完了結果が残っている場合はリセットしてから新規ジョブを積む。
  /// sourceDraftId を渡すと、全成功時にその下書きを削除し、失敗時はその id で
  /// 失敗下書きを上書き保存する（=再投稿経路で開いた下書きを更新する）。
  void enqueue({
    required String text,
    required List<Account> accounts,
    Post? inReplyToPost,
    Post? quotedPost,
    List<XFile> images = const [],
    String? sourceDraftId,
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
          images: images,
        ),
    ];
    final base0 = state.isAllDone ? const <PostJob>[] : state.jobs;
    state = ComposeQueueState(jobs: [...base0, ...newJobs]);
    _sourceDraftId = sourceDraftId;
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
      await _finalize();
    } finally {
      _running = false;
    }
  }

  /// 全ジョブ完了時に下書きを保存（失敗があれば）または該当下書きを削除
  /// （再投稿経路で全成功なら）。
  Future<void> _finalize() async {
    if (state.jobs.isEmpty) return;
    if (state.hasFailure) {
      final base = state.jobs.first;
      final failedIds = [
        for (final j in state.jobs)
          if (j.status == PostJobStatus.failure) j.account.id,
      ];
      final draft = Draft(
        id: _sourceDraftId ?? Draft.newId(),
        updatedAt: DateTime.now(),
        text: base.text,
        inReplyToPost: base.inReplyToPost,
        quotedPost: base.quotedPost,
        failedAccountIds: failedIds,
      );
      await _ref.read(draftListProvider.notifier).upsert(draft);
    } else if (_sourceDraftId != null) {
      // 再投稿経路で全成功 → 元の下書きを片付ける
      await _ref.read(draftListProvider.notifier).delete(_sourceDraftId!);
    }
    _sourceDraftId = null;
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

    // 画像があれば各画像を読み込んでリサイズして渡す（X 上限 5MB/枚、フリー前提）。
    // GIF はそのまま送信（アニメーション・色を保持）。
    List<({Uint8List bytes, String mime, String name})>? xImages;
    if (job.images.isNotEmpty) {
      xImages = [];
      for (var i = 0; i < job.images.length; i++) {
        final xfile = job.images[i];
        final raw = await xfile.readAsBytes();
        final isGif = ImageResizeService.isGifBytes(raw);
        if (isGif) {
          xImages.add((bytes: raw, mime: 'image/gif', name: 'image_$i.gif'));
        } else {
          final resized = await ImageResizeService.instance.resizeIfNeeded(
            raw,
            maxBytes: ImageResizeService.xMaxBytes,
          );
          xImages.add((
            bytes: resized,
            mime: 'image/jpeg',
            name: 'image_$i.jpg',
          ));
        }
      }
    }

    final result = await XWebViewActionService.instance.createTweet(
      job.account.xCredentials,
      job.text,
      attachmentUrl: attachmentUrl,
      inReplyToId: inReplyToId,
      images: xImages,
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

    // 画像があればリサイズ → uploadBlob → embed.images の形に組み立てる
    // GIF はアニメーションと色を保持するため再エンコードしない（そのまま送信）
    List<Map<String, dynamic>>? imageEmbeds;
    if (job.images.isNotEmpty) {
      imageEmbeds = [];
      for (final xfile in job.images) {
        final raw = await xfile.readAsBytes();
        final isGif = ImageResizeService.isGifBytes(raw);
        final Uint8List finalBytes;
        final String mimeType;
        if (isGif) {
          finalBytes = raw;
          mimeType = 'image/gif';
        } else {
          finalBytes = await ImageResizeService.instance.resizeIfNeeded(
            raw,
            maxBytes: ImageResizeService.blueskyMaxBytes,
          );
          mimeType = 'image/jpeg';
        }
        final blob = await BlueskyApiService.instance.uploadBlob(
          job.account.blueskyCredentials,
          finalBytes,
          mimeType: mimeType,
        );
        if (blob == null) {
          _updateJob(job.id,
              status: PostJobStatus.failure,
              errorMessage: 'Bluesky 画像アップロード失敗');
          _ref.read(activityLogProvider.notifier).logAction(
                action: ActivityAction.post,
                platform: SnsService.bluesky,
                accountHandle: job.account.handle,
                accountId: job.account.id,
                targetSummary: _summary(job.text),
                success: false,
                errorMessage: 'uploadBlob failed',
              );
          return;
        }
        imageEmbeds.add({'alt': '', 'image': blob});
      }
    }

    final ok = await BlueskyApiService.instance.createPost(
      job.account.blueskyCredentials,
      job.text,
      quoteUri: quoteUri,
      quoteCid: quoteCid,
      replyUri: replyUri,
      replyCid: replyCid,
      imageEmbeds: imageEmbeds,
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
