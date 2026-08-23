import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/follow_capture_engine.dart';
import 'package:mobile_omniverse/services/follow_capture_job_service.dart';
import 'package:mobile_omniverse/services/follow_db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_data.dart';

/// 走査そのものは実表示の WebView を要るので、ここでは
/// 「いつ走らせるか」「誰が WebView を握っているか」だけを見る。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final job = FollowCaptureJobService.instance;
  final db = FollowDb.instance;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db.factoryOverride = databaseFactoryFfi;
    db.pathOverride = inMemoryDatabasePath;
    await job.loadSettings();
  });

  tearDown(() async {
    // 占有カウンタは singleton なのでケースをまたいで残らないようにする
    while (job.isWebViewBusy) {
      job.releaseWebView();
    }
    job.progress.value = null;
    job.hostNeeded.value = false;
    await db.close();
    db.factoryOverride = null;
    db.pathOverride = null;
  });

  /// 完了済みスナップショットを、完了時刻を指定して 1 本作る
  Future<void> completedAt(String handle, String kind, DateTime at) async {
    final id = await db.startSnapshot(
        service: SnsService.x, targetHandle: handle, kind: kind);
    await db.finishSnapshot(
        snapshotId: id, completed: true, reason: 'terminal');
    final raw = await db.debugDatabase();
    await raw.update(
      'snapshots',
      {
        'startedAt': at.millisecondsSinceEpoch,
        'completedAt': at.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  FollowTarget target({
    String handle = 'alice',
    int followers = 0,
    int following = 0,
  }) =>
      FollowTarget(
        service: SnsService.x,
        handle: handle,
        addedAt: DateTime(2026),
        followersIntervalDays: followers,
        followingIntervalDays: following,
      );

  // ───────────────────────── 設定 ─────────────────────────

  group('設定', () {
    test('既定は自動実行あり・上限 200MB', () async {
      expect(job.autoRunOnLaunch, isTrue);
      expect(job.sizeLimitBytes, 200 * 1024 * 1024);
    });

    test('自動実行の切り替えが残る', () async {
      await job.setAutoRunOnLaunch(false);
      job.autoRunOnLaunch = true; // 読み直しで上書きされることを確かめる
      await job.loadSettings();
      expect(job.autoRunOnLaunch, isFalse);
    });

    test('保持サイズの上限が残る', () async {
      await job.setSizeLimitBytes(FollowCaptureJobService.sizeLimitChoices.first);
      job.sizeLimitBytes = -1;
      await job.loadSettings();
      expect(job.sizeLimitBytes, 50 * 1024 * 1024);
    });

    test('上限の選択肢は昇順で重複が無い', () {
      final choices = FollowCaptureJobService.sizeLimitChoices;
      expect(choices.toSet().length, choices.length);
      final sorted = [...choices]..sort();
      expect(choices, sorted);
    });
  });

  // ───────────────────────── 自動登録 ─────────────────────────

  group('自分のアカウントの自動登録', () {
    test('登録済みの印は読み直しても残る', () async {
      expect(job.isAutoRegistered('acc-1'), isFalse);
      await job.markAutoRegistered('acc-1');
      expect(job.isAutoRegistered('acc-1'), isTrue);

      await job.loadSettings();
      // 一度並べた印が消えると、削除した対象が起動のたびに復活してしまう
      expect(job.isAutoRegistered('acc-1'), isTrue);
      expect(job.isAutoRegistered('acc-2'), isFalse);
    });

    test('同じアカウントを二度印しても壊れない', () async {
      await job.markAutoRegistered('acc-1');
      await job.markAutoRegistered('acc-1');
      await job.loadSettings();
      expect(job.isAutoRegistered('acc-1'), isTrue);
    });
  });

  // ───────────────────────── 次回実行日時 ─────────────────────────

  group('次回実行日時', () {
    test('スケジュール無しなら予定は立たない', () async {
      expect(
          await FollowCaptureJobService.nextDueAt(target(), 'followers'), isNull);
    });

    test('一度も完了していなければ今すぐ', () async {
      final due = await FollowCaptureJobService.nextDueAt(
          target(followers: 1), 'followers');
      expect(due, isNotNull);
      expect(due!.isAfter(DateTime.now().add(const Duration(seconds: 1))),
          isFalse);
    });

    test('日付を基準に進むので実行時刻がずれていかない', () async {
      // 朝 9 時に終わった → 翌日は 0 時から対象になる (9 時ではない)
      await completedAt('alice', 'followers', DateTime(2026, 8, 20, 9));
      final due = await FollowCaptureJobService.nextDueAt(
          target(followers: 1), 'followers');
      expect(due, DateTime(2026, 8, 21));
    });

    test('間隔ぶんだけ日付が進む', () async {
      await completedAt('alice', 'followers', DateTime(2026, 8, 20, 9));
      final due = await FollowCaptureJobService.nextDueAt(
          target(followers: 3), 'followers');
      expect(due, DateTime(2026, 8, 23));
    });

    test('日付が変わった直後の再実行は 12 時間あける', () async {
      // 23:50 に終わって 00:10 に起動、を連続実行にしない
      await completedAt('alice', 'followers', DateTime(2026, 8, 20, 23, 50));
      final due = await FollowCaptureJobService.nextDueAt(
          target(followers: 1), 'followers');
      expect(due, DateTime(2026, 8, 21, 11, 50));
    });

    test('種別ごとに独立して数える', () async {
      await completedAt('alice', 'followers', DateTime(2026, 8, 20, 9));
      final t = target(followers: 1, following: 7);

      expect(await FollowCaptureJobService.nextDueAt(t, 'followers'),
          DateTime(2026, 8, 21));
      // following は一度も完了していないので今すぐ
      final following =
          await FollowCaptureJobService.nextDueAt(t, 'following');
      expect(following!.isAfter(DateTime(2026, 8, 21)), isTrue);
    });

    test('中断した走査は完了として数えない', () async {
      final id = await db.startSnapshot(
          service: SnsService.x, targetHandle: 'alice', kind: 'followers');
      await db.finishSnapshot(
          snapshotId: id, completed: false, reason: 'aborted', cursor: 'c');

      final due = await FollowCaptureJobService.nextDueAt(
          target(followers: 1), 'followers');
      // 未完了しか無い = まだ一度も取れていない → 今すぐ
      expect(due!.isAfter(DateTime.now().add(const Duration(seconds: 1))),
          isFalse);
    });
  });

  // ───────────────────────── WebView の占有 ─────────────────────────

  group('WebView の占有', () {
    test('確保している間だけ busy', () async {
      expect(job.isWebViewBusy, isFalse);
      await job.acquireWebView('投稿');
      expect(job.isWebViewBusy, isTrue);
      job.releaseWebView();
      expect(job.isWebViewBusy, isFalse);
    });

    test('入れ子で確保したら全部返すまで busy のまま', () async {
      await job.acquireWebView('ログイン');
      await job.acquireWebView('通知');
      job.releaseWebView();
      expect(job.isWebViewBusy, isTrue);
      job.releaseWebView();
      expect(job.isWebViewBusy, isFalse);
    });

    test('余分に返してもカウンタが負にならない', () {
      job.releaseWebView();
      job.releaseWebView();
      expect(job.isWebViewBusy, isFalse);
    });

    test('占有中は走査を始めない', () async {
      await job.acquireWebView('投稿');
      expect(
        () => job.run(
            account: makeXAccount(),
            targetHandle: 'alice',
            kind: FollowListKind.followers),
        throwsStateError,
      );
    });

    test('占有中はスケジュール実行も走らない', () async {
      await db.upsertTarget(target(followers: 1));
      await job.acquireWebView('投稿');
      await job.runDueWork(accounts: [makeXAccount()], force: true);
      expect(job.isRunning, isFalse);
      expect(job.hostNeeded.value, isFalse);
    });
  });

  // ───────────────────────── スケジュール実行の入口 ─────────────────────────

  group('スケジュール実行の入口', () {
    test('アカウントが無ければ何もしない', () async {
      await db.upsertTarget(target(followers: 1));
      await job.runDueWork(accounts: []);
      expect(job.isRunning, isFalse);
      expect(job.hostNeeded.value, isFalse);
    });

    test('自動実行が切ってあれば走らない', () async {
      await job.setAutoRunOnLaunch(false);
      await db.upsertTarget(target(followers: 1));
      await job.runDueWork(accounts: [makeXAccount()]);
      expect(job.isRunning, isFalse);
    });

    test('対象が無ければ何もせずに終わる', () async {
      await job.runDueWork(accounts: [makeXAccount()], force: true);
      expect(job.isRunning, isFalse);
      expect(job.hostNeeded.value, isFalse);
    });

    test('期日が来ていなければ走らない', () async {
      await db.upsertTarget(target(followers: 1));
      await completedAt('alice', 'followers', DateTime.now());
      await job.runDueWork(accounts: [makeXAccount()], force: true);
      expect(job.isRunning, isFalse);
      expect(job.hostNeeded.value, isFalse);
    });
  });

  // ───────────────────────── 進捗と中断 ─────────────────────────

  group('進捗と中断', () {
    FollowJobProgress progress({SnsService service = SnsService.x}) =>
        FollowJobProgress(
          snapshotId: 1,
          service: service,
          targetHandle: 'alice',
          kind: FollowListKind.followers,
          collected: 10,
          round: 2,
          startedAt: DateTime(2026, 8, 20),
        );

    test('中断を押した瞬間に表示が変わる', () {
      job.progress.value = progress();
      expect(job.progress.value!.cancelling, isFalse);

      job.cancel();
      // 実際に止まるまで数秒かかる。押した瞬間に見た目を変えないと
      // 「効いていない」と思われる
      expect(job.progress.value!.cancelling, isTrue);
      expect(job.isRunning, isTrue);
    });

    test('X の走査は WebView を取られると中断される', () async {
      job.progress.value = progress();

      final acquiring = job.acquireWebView('投稿');
      // 中断の要求は同期的に立つ。実際に止まるのを待つのはそのあと
      expect(job.progress.value!.cancelling, isTrue);

      job.progress.value = null; // 走査が止まったことにする
      await acquiring;
    });

    test('Bluesky の走査は WebView を取られても続く', () async {
      job.progress.value = progress(service: SnsService.bluesky);

      // Bluesky は WebView も x.com の Cookie も触らないので譲る理由が無い
      await job.acquireWebView('投稿');

      expect(job.progress.value!.cancelling, isFalse);
      expect(job.isRunning, isTrue);
    });

    test('待機の表示は clearWaiting で消える', () {
      final waiting = progress().copyWith(
        waitingReason: 'レート制限の解除待ち',
        waitingUntil: DateTime(2026, 8, 20, 1),
      );
      expect(waiting.waitingReason, isNotNull);

      final cleared = waiting.copyWith(clearWaiting: true);
      expect(cleared.waitingReason, isNull);
      expect(cleared.waitingUntil, isNull);
    });

    test('copyWith は渡さなかった項目を保つ', () {
      final updated = progress().copyWith(collected: 20);
      expect(updated.collected, 20);
      expect(updated.round, 2);
      expect(updated.targetHandle, 'alice');
      expect(updated.snapshotId, 1);
      expect(updated.startedAt, DateTime(2026, 8, 20));
    });
  });
}
