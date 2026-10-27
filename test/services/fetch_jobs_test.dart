import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/block_scan_service.dart';
import 'package:mobile_omniverse/services/fetch_jobs.dart';
import 'package:mobile_omniverse/services/follow_capture_engine.dart';
import 'package:mobile_omniverse/services/follow_capture_job_service.dart';
import 'package:mobile_omniverse/services/user_detail_service.dart';

import '../helpers/test_data.dart';

/// 長い取得は 1 本ずつしか走らせない
void main() {
  final jobs = FetchJobs.instance;
  final scan = BlockScanService.instance;
  final capture = FollowCaptureJobService.instance;
  final detail = UserDetailService.instance;

  BlockScanProgress scanning() => BlockScanProgress(
        runId: 1,
        targetHandle: 'alice',
        startedAt: DateTime(2026),
        done: 120,
        total: 3400,
      );

  FollowJobProgress capturing() => FollowJobProgress(
        snapshotId: 1,
        service: SnsService.x,
        targetHandle: 'bob',
        kind: FollowListKind.followers,
        collected: 1500,
        round: 3,
        startedAt: DateTime(2026),
      );

  tearDown(() {
    scan.progress.value = null;
    capture.progress.value = null;
    detail.progress.value = null;
  });

  test('何も走っていなければ空いている', () {
    expect(jobs.current.value, isNull);
    expect(jobs.isBusy, isFalse);
    expect(() => jobs.ensureIdle(FetchJobKind.blockScan), returnsNormally);
  });

  test('調査が走っている間は、ほかの取得を始められない', () {
    scan.progress.value = scanning();
    final c = jobs.current.value!;
    expect(c.kind, FetchJobKind.blockScan);
    expect(c.title, 'つながり調査 @alice');
    expect(c.detail, '120 / 3,400 人');
    expect((c.done, c.total), (120, 3400));

    expect(() => jobs.ensureIdle(FetchJobKind.followCapture),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('つながり調査 @alice'))));
    expect(() => jobs.ensureIdle(FetchJobKind.userDetail), throwsStateError);
    // 同じ種類の二重起動は、それぞれのサービスが自分で断る
    expect(() => jobs.ensureIdle(FetchJobKind.blockScan), returnsNormally);
  });

  test('フォロー/フォロワー取得は件数で見せる', () {
    capture.progress.value = capturing();
    final c = jobs.current.value!;
    expect(c.kind, FetchJobKind.followCapture);
    expect(c.title, '@bob のフォロワー');
    expect(c.detail, '1,500 件');
    expect(c.total, isNull, reason: '終わりが分からないので割合は出さない');
  });

  test('止めている間はそう出す', () {
    scan.progress.value = scanning().copyWith(cancelling: true);
    expect(jobs.current.value!.detail, '中断しています');
  });

  test('終われば空く', () {
    scan.progress.value = scanning();
    expect(jobs.isBusy, isTrue);
    scan.progress.value = null;
    expect(jobs.isBusy, isFalse);
  });

  test('画面を通らずに呼ばれても、サービス側で断る', () async {
    scan.progress.value = scanning();
    await expectLater(
      detail.start(
        account: makeXAccount(),
        service: SnsService.x,
        handle: 'alice',
        origin: 'following',
        wantBirthday: true,
        wantLastPost: false,
      ),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('つながり調査'))),
    );
  });
}
