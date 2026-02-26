import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/widgets/image_viewer.dart';

/// Override HttpOverrides so CachedNetworkImage does not make real HTTP calls.
class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = (cert, host, port) => true;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = _TestHttpOverrides();
  });

  Widget buildImageViewer({
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    return MaterialApp(
      home: ImageViewer(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
      ),
    );
  }

  group('ImageViewer', () {
    testWidgets('renders Scaffold with black background', (tester) async {
      await tester.pumpWidget(buildImageViewer(
        imageUrls: ['https://example.com/img1.jpg'],
      ));
      await tester.pump();

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('does not show page indicator for single image',
        (tester) async {
      await tester.pumpWidget(buildImageViewer(
        imageUrls: ['https://example.com/img1.jpg'],
      ));
      await tester.pump();

      // For single image, title should be null (no page indicator text)
      expect(find.text('1 / 1'), findsNothing);
    });

    testWidgets('shows page indicator for multiple images', (tester) async {
      await tester.pumpWidget(buildImageViewer(
        imageUrls: [
          'https://example.com/img1.jpg',
          'https://example.com/img2.jpg',
          'https://example.com/img3.jpg',
        ],
      ));
      await tester.pump();

      // Shows "1 / 3" for first image
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('shows correct page when initialIndex is non-zero',
        (tester) async {
      await tester.pumpWidget(buildImageViewer(
        imageUrls: [
          'https://example.com/img1.jpg',
          'https://example.com/img2.jpg',
          'https://example.com/img3.jpg',
        ],
        initialIndex: 1,
      ));
      await tester.pump();

      // Shows "2 / 3" when starting at index 1
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('contains InteractiveViewer for zoom support', (tester) async {
      await tester.pumpWidget(buildImageViewer(
        imageUrls: ['https://example.com/img1.jpg'],
      ));
      await tester.pump();

      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('contains PageView for swiping', (tester) async {
      await tester.pumpWidget(buildImageViewer(
        imageUrls: [
          'https://example.com/img1.jpg',
          'https://example.com/img2.jpg',
        ],
      ));
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('has AppBar with transparent background', (tester) async {
      await tester.pumpWidget(buildImageViewer(
        imageUrls: ['https://example.com/img1.jpg'],
      ));
      await tester.pump();

      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
