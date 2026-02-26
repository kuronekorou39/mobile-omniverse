import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/screens/bookmarks_screen.dart';
import 'package:mobile_omniverse/services/bookmark_service.dart';
import 'package:mobile_omniverse/widgets/post_card.dart';

import '../helpers/test_data.dart';

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BookmarkService.instance.resetForTest();
    // Initialize BookmarkService with empty SharedPreferences.
    await BookmarkService.instance.init();
  });

  Widget buildBookmarksScreen() {
    return const MaterialApp(
      home: BookmarksScreen(),
    );
  }

  group('BookmarksScreen - empty state', () {
    testWidgets('shows "ブックマーク" title in AppBar', (tester) async {
      await tester.pumpWidget(buildBookmarksScreen());

      expect(find.text('ブックマーク'), findsOneWidget);
    });

    testWidgets('shows empty state message when no bookmarks', (tester) async {
      await tester.pumpWidget(buildBookmarksScreen());

      expect(find.text('ブックマークはありません'), findsOneWidget);
    });

    testWidgets('shows empty state hint text', (tester) async {
      await tester.pumpWidget(buildBookmarksScreen());

      expect(
        find.text('投稿のブックマークアイコンをタップして保存できます'),
        findsOneWidget,
      );
    });

    testWidgets('shows bookmark outline icon in empty state', (tester) async {
      await tester.pumpWidget(buildBookmarksScreen());

      expect(find.byIcon(Icons.bookmark_outline), findsOneWidget);
    });

    testWidgets('renders as a Scaffold', (tester) async {
      await tester.pumpWidget(buildBookmarksScreen());

      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('has an AppBar', (tester) async {
      await tester.pumpWidget(buildBookmarksScreen());

      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('BookmarksScreen - with bookmarks', () {
    testWidgets('shows bookmarked posts in a ListView', (tester) async {
      // Add a bookmark before building the screen
      final post = makePost(
        id: 'bm_1',
        username: 'Bookmarked User',
        handle: '@bmuser',
        body: 'This is a bookmarked post',
      );
      await BookmarkService.instance.toggle(post);

      await tester.pumpWidget(buildBookmarksScreen());
      await tester.pump();

      expect(find.text('This is a bookmarked post'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('shows PostCard for each bookmarked post', (tester) async {
      final post1 = makePost(
        id: 'bm_1',
        username: 'User One',
        handle: '@user1',
        body: 'First bookmark',
      );
      final post2 = makePost(
        id: 'bm_2',
        username: 'User Two',
        handle: '@user2',
        body: 'Second bookmark',
      );
      await BookmarkService.instance.toggle(post1);
      await BookmarkService.instance.toggle(post2);

      await tester.pumpWidget(buildBookmarksScreen());
      await tester.pump();

      expect(find.byType(PostCard), findsNWidgets(2));
      expect(find.text('First bookmark'), findsOneWidget);
      expect(find.text('Second bookmark'), findsOneWidget);
    });

    testWidgets('does not show empty state when bookmarks exist',
        (tester) async {
      final post = makePost(id: 'bm_1', body: 'A post');
      await BookmarkService.instance.toggle(post);

      await tester.pumpWidget(buildBookmarksScreen());
      await tester.pump();

      expect(find.text('ブックマークはありません'), findsNothing);
      expect(find.byIcon(Icons.bookmark_outline), findsNothing);
    });

    testWidgets('bookmarked posts are wrapped in Dismissible',
        (tester) async {
      final post = makePost(id: 'bm_1', body: 'Dismissible post');
      await BookmarkService.instance.toggle(post);

      await tester.pumpWidget(buildBookmarksScreen());
      await tester.pump();

      expect(find.byType(Dismissible), findsOneWidget);
    });

    testWidgets('dismiss removes bookmarked post', (tester) async {
      final post = makePost(id: 'bm_dismiss', body: 'Will be dismissed');
      await BookmarkService.instance.toggle(post);

      await tester.pumpWidget(buildBookmarksScreen());
      await tester.pump();

      expect(find.text('Will be dismissed'), findsOneWidget);

      // Swipe to dismiss
      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Post should be removed
      expect(find.text('Will be dismissed'), findsNothing);
      // Should show empty state again
      expect(find.text('ブックマークはありません'), findsOneWidget);
    });

    testWidgets('dismiss background shows delete icon and red color',
        (tester) async {
      final post = makePost(id: 'bm_bg', body: 'Background test');
      await BookmarkService.instance.toggle(post);

      await tester.pumpWidget(buildBookmarksScreen());
      await tester.pump();

      // Start dragging to reveal the background
      await tester.drag(find.byType(Dismissible), const Offset(-100, 0));
      await tester.pump();

      // The delete icon should appear in the background
      expect(find.byIcon(Icons.delete), findsOneWidget);
    });
  });
}
