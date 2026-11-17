import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/widgets/hiding_header_scaffold.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HidingHeaderScaffold(
        appBar: AppBar(title: const Text('見出し')),
        body: ListView(
          children: [
            for (var i = 0; i < 60; i++)
              SizedBox(height: 48, child: Text('行$i')),
          ],
        ),
      ),
    ));
  }

  // ヘッダーの下端の位置 = 画面に出ている高さ（テストではステータスバーが無い）
  double headerHeight(WidgetTester tester) {
    final finder = find.byType(AppBar, skipOffstage: false);
    if (finder.evaluate().isEmpty) return 0;
    return tester.getRect(finder).bottom.clamp(0, double.infinity);
  }

  testWidgets('下へ送るとヘッダーが隠れ、上へ戻すと出る', (tester) async {
    await pump(tester);
    expect(headerHeight(tester), kToolbarHeight);

    await tester.drag(find.text('行3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(headerHeight(tester), 0);

    // 指についてくる。少し戻すと少しだけ出る
    await tester.drag(find.byType(ListView), const Offset(0, 20));
    await tester.pumpAndSettle();
    expect(headerHeight(tester), closeTo(20, 1));

    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(headerHeight(tester), kToolbarHeight);
  });

  testWidgets('隠れる間、一覧は指と同じだけ動く', (tester) async {
    await pump(tester);
    final before = tester.getTopLeft(find.text('行5')).dy;
    final gesture = await tester.startGesture(tester.getCenter(find.text('行5')));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(tester.getTopLeft(find.text('行5')).dy, closeTo(before - 50, 1));
    await gesture.up();
  });

  testWidgets('先頭まで戻ればヘッダーは出ている', (tester) async {
    await pump(tester);
    await tester.drag(find.text('行3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, 2000), 3000);
    await tester.pumpAndSettle();
    expect(find.text('行0'), findsOneWidget);
    expect(headerHeight(tester), kToolbarHeight);
  });
}
