import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/providers/compose_queue_provider.dart';
import 'package:mobile_omniverse/widgets/compose_queue_banner.dart';

import '../helpers/test_data.dart';

/// 状態を外から差し込むだけの notifier。投稿処理は走らせない
class _FixedQueue extends ComposeQueueNotifier {
  _FixedQueue(super.ref, ComposeQueueState initial) {
    state = initial;
  }
}

/// 画面幅 400 で、下のバーの上に重ねたときの形で組む
Future<void> pumpBanner(WidgetTester tester, ComposeQueueState state) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        composeQueueProvider.overrideWith((ref) => _FixedQueue(ref, state)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ComposeQueueBanner(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

PostJob job(String id, PostJobStatus status, {String handle = '@xuser'}) =>
    PostJob(
      id: id,
      text: 'hello',
      account: makeXAccount(id: id, handle: handle),
      status: status,
    );

void main() {
  group('ComposeQueueBanner', () {
    testWidgets('投稿中は中身ぶんの幅で中央に出て、画面いっぱいには広がらない',
        (tester) async {
      await pumpBanner(tester,
          ComposeQueueState(jobs: [job('a', PostJobStatus.posting)]));

      expect(find.text('投稿しています…'), findsOneWidget);
      final banner = tester.getRect(find.byType(Material).last);
      expect(banner.width, lessThan(300));
      expect((banner.center.dx - 200).abs(), lessThan(1), reason: '中央');
      // FAB（端から 16、幅 56）の内側には入らない
      expect(banner.left, greaterThan(16 + 56));
      expect(banner.right, lessThan(400 - 16 - 56));
    });

    testWidgets('複数件は進み具合の帯が面の幅いっぱいに出る', (tester) async {
      await pumpBanner(
          tester,
          ComposeQueueState(jobs: [
            job('a', PostJobStatus.success, handle: '@one'),
            job('b', PostJobStatus.posting, handle: '@two'),
            job('c', PostJobStatus.pending, handle: '@three'),
          ]));

      expect(find.text('@two に投稿中 2/3'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final bar = tester.getRect(find.byType(LinearProgressIndicator));
      final banner = tester.getRect(find.byType(Material).last);
      expect(bar.width, greaterThan(banner.width * 0.7));
    });

    testWidgets('失敗は再投稿と閉じるが並んでも FAB の範囲に掛からない',
        (tester) async {
      await pumpBanner(tester,
          ComposeQueueState(jobs: [job('a', PostJobStatus.failure)]));

      expect(find.text('投稿に失敗'), findsOneWidget);
      expect(find.text('再投稿'), findsOneWidget);
      expect(find.byTooltip('閉じる'), findsOneWidget);
      final banner = tester.getRect(find.byType(Material).last);
      expect(banner.left, greaterThan(16 + 56));
      expect(banner.right, lessThan(400 - 16 - 56));
      // 文が省略されていないこと
      final text = tester.widget<Text>(find.text('投稿に失敗'));
      final painter = TextPainter(
        text: TextSpan(text: '投稿に失敗', style: text.style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(tester.getSize(find.text('投稿に失敗')).width,
          greaterThanOrEqualTo(painter.width - 0.5));
    });

    testWidgets('何も無いときは場所を取らない', (tester) async {
      await pumpBanner(tester, const ComposeQueueState());
      expect(tester.getSize(find.byType(ComposeQueueBanner)).height, 0);
    });
  });
}
