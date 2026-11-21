import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/widgets/fetch_start_dialog.dart';

void main() {
  Future<void> pump(WidgetTester tester, {VoidCallback? onStart, Size? size}) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FetchStartDialog(
          title: 'つながり調査',
          targets: const [
            FetchTargetChoice('following', 'フォロー', count: 356),
            FetchTargetChoice('followers', 'フォロワー', count: 1284),
            FetchTargetChoice('both', '両方', count: 1284),
            FetchTargetChoice('mutual', '相互', enabled: false),
          ],
          selected: 'following',
          onSelected: (_) {},
          optionsLabel: '記録する内容',
          options: [
            FetchOption('人気', value: true, onChanged: (_) {}),
            FetchOption('つながり', value: false, onChanged: (_) {}),
          ],
          summary: const Text('356人・目安 約3時間'),
          onStart: onStart,
        ),
      ),
    ));
  }

  testWidgets('対象に人数を添え、要約と開始を出す', (tester) async {
    await pump(tester, onStart: () {});
    expect(find.text('フォロー 356'), findsOneWidget);
    expect(find.text('フォロワー 1,284'), findsOneWidget);
    expect(find.text('356人・目安 約3時間'), findsOneWidget);
    expect(find.text('開始'), findsOneWidget);
  });

  testWidgets('開始できないときはボタンを押せない', (tester) async {
    await pump(tester);
    final button =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '開始'));
    expect(button.onPressed, isNull);
  });

  testWidgets('横向きの低い画面でも要約と開始ボタンが画面に収まる', (tester) async {
    const size = Size(915, 300);
    await pump(tester, onStart: () {}, size: size);
    expect(tester.getRect(find.text('356人・目安 約3時間')).bottom,
        lessThanOrEqualTo(size.height));
    expect(tester.getRect(find.text('開始')).bottom,
        lessThanOrEqualTo(size.height));
  });
}
