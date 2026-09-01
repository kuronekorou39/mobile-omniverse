import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/widgets/appear_once.dart';

void main() {
  group('AppearOnce', () {
    testWidgets('演出ありのときは透明から始まって出来上がる', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: AppearOnce(child: Text('新着')),
      ));

      // 始まった直後はまだ見えていない
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);

      await tester.pump(const Duration(milliseconds: 160));
      final mid = tester.widget<Opacity>(find.byType(Opacity)).opacity;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));

      await tester.pumpAndSettle();
      // 出来上がったら余計なウィジェットを挟まない
      expect(find.byType(Opacity), findsNothing);
      expect(find.text('新着'), findsOneWidget);
    });

    testWidgets('演出なしのときは最初から出来上がっている', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: AppearOnce(enabled: false, child: Text('既存')),
      ));

      // スクロールで再構築されただけの行が毎回動くと落ち着かない
      expect(find.byType(Opacity), findsNothing);
      expect(find.text('既存'), findsOneWidget);
    });

    testWidgets('高さも一緒に開くので、下の行が押しのけられる', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: AppearOnce(child: SizedBox(height: 100, width: 100)),
        ),
      ));

      // 始まった時点では高さを取らない = 下の行を押しのけない
      expect(tester.getSize(find.byType(AppearOnce)).height, 0);

      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppearOnce)).height, 100);
    });
  });

  group('NewItemTracker', () {
    test('最初の読み込みでは演出しない', () {
      final t = NewItemTracker();
      // 起動のたびに全部が波打つのは落ち着かない
      expect(t.isNew('a'), isFalse);
      expect(t.isNew('b'), isFalse);
    });

    test('覚えたあとに現れたものだけ新着', () {
      final t = NewItemTracker()..remember(['a', 'b']);

      expect(t.isNew('a'), isFalse);
      expect(t.isNew('c'), isTrue);
    });

    test('一度覚えた新着は次からは新着ではない', () {
      final t = NewItemTracker()..remember(['a']);
      expect(t.isNew('b'), isTrue);

      t.remember(['a', 'b']);
      expect(t.isNew('b'), isFalse);
    });

    test('リセットすると初回の扱いに戻る', () {
      final t = NewItemTracker()..remember(['a']);
      expect(t.isNew('b'), isTrue);

      t.reset();
      expect(t.isNew('b'), isFalse);
    });
  });
}
