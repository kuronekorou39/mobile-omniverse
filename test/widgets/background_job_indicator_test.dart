import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/services/block_scan_service.dart';
import 'package:mobile_omniverse/services/follow_capture_engine.dart';
import 'package:mobile_omniverse/services/follow_capture_job_service.dart';
import 'package:mobile_omniverse/widgets/background_job_indicator.dart';

void main() {
  final job = FollowCaptureJobService.instance;
  final scan = BlockScanService.instance;

  tearDown(() {
    job.progress.value = null;
    scan.progress.value = null;
  });

  Widget wrap() => const MaterialApp(
        home: Scaffold(body: BackgroundJobIndicator()),
      );

  testWidgets('何も走っていなければ出さない', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('つながり調査が走っていれば出る', (tester) async {
    scan.progress.value = BlockScanProgress(
      runId: 1,
      targetHandle: 'rou39',
      startedAt: DateTime(2026, 9, 7),
      done: 40,
      total: 100,
    );
    await tester.pumpWidget(wrap());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.hub), findsOneWidget);
  });

  // 進みが分かるときは、回り続けるだけでなく割合を出す
  testWidgets('人数が分かれば進みの割合を出す', (tester) async {
    scan.progress.value = BlockScanProgress(
      runId: 1,
      targetHandle: 'rou39',
      startedAt: DateTime(2026, 9, 7),
      done: 40,
      total: 100,
    );
    await tester.pumpWidget(wrap());
    final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(indicator.value, closeTo(0.4, 0.001));
  });

  testWidgets('走り始めで総数が0なら回すだけ', (tester) async {
    scan.progress.value = BlockScanProgress(
      runId: 1,
      targetHandle: 'rou39',
      startedAt: DateTime(2026, 9, 7),
    );
    await tester.pumpWidget(wrap());
    final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(indicator.value, isNull);
  });

  testWidgets('フォロー取得が走っていれば出る', (tester) async {
    job.progress.value = FollowJobProgress(
      snapshotId: 1,
      service: SnsService.x,
      targetHandle: 'rou39',
      kind: FollowListKind.followers,
      startedAt: DateTime(2026, 9, 7),
      collected: 1200,
      round: 6,
    );
    await tester.pumpWidget(wrap());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
  });
}
