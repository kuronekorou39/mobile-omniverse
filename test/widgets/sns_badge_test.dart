import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/widgets/sns_badge.dart';

void main() {
  group('SnsBadge', () {
    Widget buildBadge(SnsService service) {
      return MaterialApp(
        home: Scaffold(body: SnsBadge(service: service)),
      );
    }

    testWidgets('X badge shows double-struck X text', (tester) async {
      await tester.pumpWidget(buildBadge(SnsService.x));

      // SnsBadge uses Unicode double-struck capital X (\u{1D54F})
      expect(find.text('\u{1D54F}'), findsOneWidget);
    });

    testWidgets('Bluesky badge shows double-struck B text', (tester) async {
      await tester.pumpWidget(buildBadge(SnsService.bluesky));

      // SnsBadge uses Unicode double-struck capital B (\u{1D539})
      expect(find.text('\u{1D539}'), findsOneWidget);
    });

    testWidgets('X badge has black background', (tester) async {
      await tester.pumpWidget(buildBadge(SnsService.x));

      // SnsBadge is wrapped in Opacity > Container
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(Opacity),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.black);
    });

    testWidgets('Bluesky badge has blue background', (tester) async {
      await tester.pumpWidget(buildBadge(SnsService.bluesky));

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(Opacity),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF0085FF));
    });
  });
}
