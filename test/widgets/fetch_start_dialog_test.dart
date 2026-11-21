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
            FetchTargetChoice('following', 'フォロー', count: 356, detail: '約3時間'),
            FetchTargetChoice('followers', 'フォロワー', count: 1284, detail: '約9時間'),
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
          summary: const Text('保存 約26 MB'),
          onStart: onStart,
        ),
      ),
    ));
  }

  testWidgets('対象ごとに人数と時間を並べ、要約と開始を出す', (tester) async {
    await pump(tester, onStart: () {});
    expect(find.text('356人'), findsOneWidget);
    expect(find.text('1,284人'), findsNWidgets(2));
    expect(find.text('約9時間'), findsOneWidget);
    expect(find.byType(Radio<String>), findsNWidgets(4));
    expect(find.text('保存 約26 MB'), findsOneWidget);
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
    expect(tester.getRect(find.text('保存 約26 MB')).bottom,
        lessThanOrEqualTo(size.height));
    expect(tester.getRect(find.text('開始')).bottom,
        lessThanOrEqualTo(size.height));
  });
}
