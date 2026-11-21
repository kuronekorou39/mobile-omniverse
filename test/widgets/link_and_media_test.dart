import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_omniverse/utils/app_snackbar.dart';
import 'package:mobile_omniverse/widgets/post_media.dart';

void main() {
  group('本文のリンク', () {
    testWidgets('タップすると、すぐには開かず行き先を見せて確かめる', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: LinkedText(text: '見てね https://example.com/a/b?c=1 です'),
        ),
      ));

      await tester.tap(find.text('https://example.com/a/b?c=1'));
      await tester.pumpAndSettle();

      expect(find.text('リンクを開きますか？'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(find.text('リンクを開きますか？'), findsNothing);
    });
  });

  group('画像の並び', () {
    List<String> urls(int n) =>
        [for (var i = 0; i < n; i++) 'https://example.com/$i.jpg'];

    testWidgets('5 枚以上なら 4 枚目に残りの枚数を出す', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PostImageGrid(imageUrls: urls(20))),
      ));
      expect(find.text('+16'), findsOneWidget);
    });

    testWidgets('4 枚ちょうどなら枚数は出さない', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PostImageGrid(imageUrls: urls(4))),
      ));
      expect(find.textContaining('+'), findsNothing);
    });
  });

  group('失敗の説明', () {
    test('通信が切れたときは URL や英語を出さずに言い換える', () {
      final e = http.ClientException('Software caused connection abort',
          Uri.parse('https://x.com/i/api/graphql/abc/TweetDetail?variables=x'));
      final text = describeError(e);
      expect(text, contains('通信できませんでした'));
      expect(text, isNot(contains('x.com')));
      expect(describeError(const SocketException('failed')),
          contains('通信できませんでした'));
    });

    test('それ以外は短く切って出す', () {
      expect(describeError(Exception('${'a' * 200}')).length, lessThan(100));
    });
  });
}
