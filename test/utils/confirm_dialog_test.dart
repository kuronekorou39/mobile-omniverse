import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/utils/confirm_dialog.dart';

/// HomeScreen と同じく「タブごとの入れ子 Navigator」の中に画面を置く。
///
/// showDialog は既定でルート Navigator に載るので、画面の context で pop すると
/// ダイアログではなく画面自体が閉じてしまう。その取り違えを踏まないことを見る。
Widget _appWithTabNavigator({required void Function(bool) onResult}) {
  return MaterialApp(
    home: Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => Scaffold(
          body: Builder(
            builder: (inner) => TextButton(
              onPressed: () async => onResult(await confirmDialog(
                inner,
                title: '@someone を削除',
                message: '元に戻せません',
                confirmLabel: '削除',
                destructive: true,
              )),
              child: const Text('画面のボタン'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('タブの入れ子 Navigator の中でも、確定すると true が返る', (tester) async {
    bool? result;
    await tester.pumpWidget(_appWithTabNavigator(onResult: (v) => result = v));

    await tester.tap(find.text('画面のボタン'));
    await tester.pumpAndSettle();
    expect(find.text('削除'), findsOneWidget);

    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    // 閉じるのはダイアログだけ。呼び出し元の画面は残っている
    expect(find.text('画面のボタン'), findsOneWidget);
    expect(find.text('元に戻せません'), findsNothing);
  });

  testWidgets('キャンセルすると false が返り、画面もそのまま', (tester) async {
    bool? result;
    await tester.pumpWidget(_appWithTabNavigator(onResult: (v) => result = v));

    await tester.tap(find.text('画面のボタン'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('画面のボタン'), findsOneWidget);
  });

  testWidgets('バリアで閉じられたら false 扱い', (tester) async {
    bool? result;
    await tester.pumpWidget(_appWithTabNavigator(onResult: (v) => result = v));

    await tester.tap(find.text('画面のボタン'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10)); // バリアをタップ
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
