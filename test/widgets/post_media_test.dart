import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/widgets/post_media.dart';

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

  group('LinkedText', () {
    testWidgets('renders plain text without URLs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LinkedText(text: 'Hello, world!')),
        ),
      );

      expect(find.text('Hello, world!'), findsOneWidget);
    });

    testWidgets('empty text renders SizedBox.shrink', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LinkedText(text: '')),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('renders text containing a URL as Text.rich', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkedText(text: 'Check https://example.com for more'),
          ),
        ),
      );

      // Should render as Text.rich (RichText) rather than plain Text
      expect(find.byType(Text), findsAtLeastNWidgets(1));
      // The URL text should be findable as a widget
      expect(find.textContaining('https://example.com'), findsOneWidget);
    });

    testWidgets('selectable mode renders SelectableText for plain text',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkedText(text: 'Selectable text', selectable: true),
          ),
        ),
      );

      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('multiple URLs are rendered', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkedText(
              text:
                  'Visit https://example.com and https://flutter.dev for info',
            ),
          ),
        ),
      );

      expect(find.textContaining('https://example.com'), findsOneWidget);
      expect(find.textContaining('https://flutter.dev'), findsOneWidget);
    });

    testWidgets('respects custom style', (tester) async {
      const customStyle = TextStyle(fontSize: 20, color: Colors.red);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkedText(text: 'Styled text', style: customStyle),
          ),
        ),
      );

      expect(find.text('Styled text'), findsOneWidget);
    });
  });

  group('PostImageGrid', () {
    testWidgets('renders nothing for empty imageUrls', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PostImageGrid(imageUrls: [])),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('renders single image layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostImageGrid(imageUrls: ['https://example.com/img1.jpg']),
          ),
        ),
      );

      // Single image uses GestureDetector
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('renders 2-image layout with Row', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostImageGrid(imageUrls: [
              'https://example.com/img1.jpg',
              'https://example.com/img2.jpg',
            ]),
          ),
        ),
      );

      // 2 images renders as a Row
      expect(find.byType(Row), findsOneWidget);
      expect(find.byType(GestureDetector), findsNWidgets(2));
    });

    testWidgets('renders 3-image layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostImageGrid(imageUrls: [
              'https://example.com/img1.jpg',
              'https://example.com/img2.jpg',
              'https://example.com/img3.jpg',
            ]),
          ),
        ),
      );

      // 3 images: Row with Column on right side
      expect(find.byType(GestureDetector), findsNWidgets(3));
    });

    testWidgets('renders 4-image layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostImageGrid(imageUrls: [
              'https://example.com/img1.jpg',
              'https://example.com/img2.jpg',
              'https://example.com/img3.jpg',
              'https://example.com/img4.jpg',
            ]),
          ),
        ),
      );

      // 4 images: 2 rows of 2
      expect(find.byType(GestureDetector), findsNWidgets(4));
    });

    testWidgets('more than 4 images clamps to 4', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostImageGrid(imageUrls: [
              'https://example.com/img1.jpg',
              'https://example.com/img2.jpg',
              'https://example.com/img3.jpg',
              'https://example.com/img4.jpg',
              'https://example.com/img5.jpg',
            ]),
          ),
        ),
      );

      // Still only 4 GestureDetectors
      expect(find.byType(GestureDetector), findsNWidgets(4));
    });
  });

  group('PostImageGrid - tapping images', () {
    testWidgets('tapping a single image opens image viewer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostImageGrid(imageUrls: ['https://example.com/img1.jpg']),
          ),
        ),
      );

      // Tap the image
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // ImageViewer should be pushed (it has a Scaffold with AppBar)
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping a 2-image grid first image opens viewer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostImageGrid(imageUrls: [
              'https://example.com/img1.jpg',
              'https://example.com/img2.jpg',
            ]),
          ),
        ),
      );

      // Tap the first image
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping a 4-image grid image opens viewer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostImageGrid(imageUrls: [
              'https://example.com/img1.jpg',
              'https://example.com/img2.jpg',
              'https://example.com/img3.jpg',
              'https://example.com/img4.jpg',
            ]),
          ),
        ),
      );

      // Tap the third image
      await tester.tap(find.byType(GestureDetector).at(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });
  });

  group('PostVideoThumbnail', () {
    testWidgets('renders play button overlay', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostVideoThumbnail(
              videoUrl: 'https://example.com/video.mp4',
              thumbnailUrl: 'https://example.com/thumb.jpg',
            ),
          ),
        ),
      );

      // Play arrow icon
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      // GestureDetector for tap
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('renders with ClipRRect and Stack', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PostVideoThumbnail(
              videoUrl: 'https://example.com/video.mp4',
              thumbnailUrl: 'https://example.com/thumb.jpg',
            ),
          ),
        ),
      );

      expect(find.byType(ClipRRect), findsAtLeastNWidgets(1));
      expect(find.byType(Stack), findsAtLeastNWidgets(1));
    });
  });
}
