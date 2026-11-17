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

  double headerHeight(WidgetTester tester) =>
      tester.getSize(find.byType(SizeTransition)).height;

  testWidgets('下へ送るとヘッダーが隠れ、上へ戻すと出る', (tester) async {
    await pump(tester);
    expect(headerHeight(tester), kToolbarHeight);

    await tester.drag(find.text('行3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(headerHeight(tester), 0);

    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(headerHeight(tester), kToolbarHeight);
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
