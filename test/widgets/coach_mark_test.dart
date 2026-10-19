import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/widgets/onboarding/coach_mark.dart';

void main() {
  group('showCoachMarkTour', () {
    final keys = List.generate(3, (_) => GlobalKey());

    Widget app() => MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ListView(
                children: [
                  for (var i = 0; i < keys.length; i++)
                    // 3 つ目は画面外に置き、スクロールして見せられるか確かめる
                    SizedBox(key: keys[i], height: i == 2 ? 900 : 100),
                ],
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () => showCoachMarkTour(context, steps: [
                  for (var i = 0; i < keys.length; i++)
                    CoachMarkStep(
                        targetKey: keys[i], title: 'T$i', message: 'M$i'),
                ]),
              ),
            ),
          ),
        );

    testWidgets('次へで順に進み、最後の OK で閉じる', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('T0'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);

      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      expect(find.text('T1'), findsOneWidget);

      await tester.tap(find.text('次へ'));
      await tester.pumpAndSettle();
      expect(find.text('T2'), findsOneWidget);
      expect(find.text('スキップ'), findsNothing);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('T2'), findsNothing);
    });

    testWidgets('スキップで途中でも閉じる', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('スキップ'));
      await tester.pumpAndSettle();
      expect(find.text('T0'), findsNothing);
    });

    testWidgets('暗い部分をタップしても閉じない', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(5, 590));
      await tester.pumpAndSettle();
      expect(find.text('T0'), findsOneWidget);
    });
  });
}
