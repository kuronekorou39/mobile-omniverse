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

    testWidgets('X badge shows "X" text', (tester) async {
      await tester.pumpWidget(buildBadge(SnsService.x));

      expect(find.text('X'), findsOneWidget);
    });

    testWidgets('Bluesky badge shows "Bluesky" text', (tester) async {
      await tester.pumpWidget(buildBadge(SnsService.bluesky));

      expect(find.text('Bluesky'), findsOneWidget);
    });

    testWidgets('X badge has black background', (tester) async {
      await tester.pumpWidget(buildBadge(SnsService.x));

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.black);
    });

    testWidgets('Bluesky badge has blue background', (tester) async {
      await tester.pumpWidget(buildBadge(SnsService.bluesky));

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF0085FF));
    });
  });
}
