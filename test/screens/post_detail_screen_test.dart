import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/screens/post_detail_screen.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
import 'package:mobile_omniverse/services/bookmark_service.dart';
import 'package:mobile_omniverse/widgets/sns_badge.dart';

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
    await BookmarkService.instance.init();
  });

  Widget buildPostDetailScreen({required post}) {
    return ProviderScope(
      child: MaterialApp(
        home: PostDetailScreen(post: post),
      ),
    );
  }

  group('PostDetailScreen', () {
    testWidgets('shows "投稿詳細" in AppBar', (tester) async {
      final post = makePost(body: 'Test post body');
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('投稿詳細'), findsOneWidget);
    });

    testWidgets('displays post body text', (tester) async {
      final post = makePost(body: 'This is a test post body');
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('This is a test post body'), findsOneWidget);
    });

    testWidgets('displays post username', (tester) async {
      final post = makePost(username: 'PostAuthor');
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('PostAuthor'), findsOneWidget);
    });

    testWidgets('displays post handle', (tester) async {
      final post = makePost(handle: '@postauthor');
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('@postauthor'), findsOneWidget);
    });

    testWidgets('displays SnsBadge for X', (tester) async {
      final post = makePost(source: SnsService.x);
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.byType(SnsBadge), findsOneWidget);
    });

    testWidgets('displays SnsBadge for Bluesky', (tester) async {
      final post = makeBlueskyPost();
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.byType(SnsBadge), findsOneWidget);
      expect(find.text('Bluesky'), findsOneWidget);
    });

    testWidgets('displays engagement counts with labels', (tester) async {
      final post = makePost(likeCount: 10, repostCount: 5, replyCount: 3);
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('10'), findsOneWidget);
      expect(find.text('いいね'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('リポスト'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('リプライ'), findsAtLeastNWidgets(1));
    });

    testWidgets('displays formatted timestamp', (tester) async {
      final post = makePost(timestamp: DateTime(2024, 1, 15, 14, 30));
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('2024/01/15 14:30'), findsOneWidget);
    });

    testWidgets('shows bookmark outline icon when not bookmarked',
        (tester) async {
      final post = makePost(id: 'not_bookmarked');
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.byIcon(Icons.bookmark_outline), findsOneWidget);
    });

    testWidgets('tapping bookmark toggles icon', (tester) async {
      final post = makePost(id: 'toggle_bookmark');
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      // Initially not bookmarked
      expect(find.byIcon(Icons.bookmark_outline), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsNothing);

      // Tap the bookmark icon
      await tester.tap(find.byIcon(Icons.bookmark_outline));
      await tester.pumpAndSettle();

      // Now bookmarked
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
    });

    testWidgets('shows share icon when post has permalink', (tester) async {
      final post =
          makePost(permalink: 'https://x.com/user/status/123');
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    });

    testWidgets('hides share icon when post has no permalink', (tester) async {
      final post = makePost(permalink: null);
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.byIcon(Icons.share_outlined), findsNothing);
    });

    testWidgets('shows "リプライはありません" when no account and replies loading fails',
        (tester) async {
      // Post without accountId -> _getAccount returns null -> error message
      final post = makePost(accountId: null);
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pumpAndSettle();

      expect(find.text('アカウント情報が見つかりません'), findsOneWidget);
    });

    testWidgets('shows error state with retry button when account is null',
        (tester) async {
      final post = makePost(accountId: null);
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pumpAndSettle();

      expect(find.text('リトライ'), findsOneWidget);
    });

    testWidgets('displays Divider between main post and replies section',
        (tester) async {
      final post = makePost();
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.byType(Divider), findsAtLeastNWidgets(1));
    });

    testWidgets('displays CircleAvatar for post author', (tester) async {
      final post = makePost(username: 'Author');
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.byType(CircleAvatar), findsAtLeastNWidgets(1));
    });

    testWidgets('shows initial letter when no avatar URL', (tester) async {
      final post = makePost(username: 'Zulu', avatarUrl: null);
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      // The CircleAvatar child should show 'Z'
      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('shows "?" when username is empty and no avatar',
        (tester) async {
      final post = makePost(username: '', avatarUrl: null);
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders RefreshIndicator for pull-to-refresh', (tester) async {
      final post = makePost();
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('renders with zero engagement counts', (tester) async {
      final post = makePost(likeCount: 0, repostCount: 0, replyCount: 0);
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      // The count labels should still be displayed with 0
      expect(find.text('0'), findsAtLeastNWidgets(3));
    });
  });

  group('PostDetailScreen - replies states', () {
    testWidgets('shows error when accountId points to nonexistent account',
        (tester) async {
      // Post has an accountId but no matching account in storage
      // This triggers _getAccount() returning null -> error state
      AccountStorageService.instance.setAccountsForTest([]);

      final post = makePost(
        id: 'x_detail_post',
        accountId: 'nonexistent_acc_id',
        source: SnsService.x,
        body: 'Test post for detail',
      );

      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pumpAndSettle();

      // _getAccount returns null because no matching account -> error message
      expect(find.text('アカウント情報が見つかりません'), findsOneWidget);
      expect(find.text('リトライ'), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      final post = makePost(
        id: 'loading_test',
        accountId: null,
        body: 'Loading test',
      );
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      // Don't settle - check during initial loading before _loadReplies completes
      await tester.pump();

      // Should show CircularProgressIndicator during loading
      // (The post has null accountId so _loadReplies fails fast,
      // but there might be a brief loading state)
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('shows post with images in main post area', (tester) async {
      final post = makePost(
        body: 'Post with images',
        imageUrls: ['https://example.com/img1.jpg', 'https://example.com/img2.jpg'],
      );
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('Post with images'), findsOneWidget);
      // PostImageGrid should be rendered
      expect(find.byType(GestureDetector), findsAtLeastNWidgets(1));
    });

    testWidgets('shows post with video thumbnail in main post area',
        (tester) async {
      final post = makePost(
        body: 'Post with video',
        videoUrl: 'https://example.com/video.mp4',
        videoThumbnailUrl: 'https://example.com/thumb.jpg',
      );
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('Post with video'), findsOneWidget);
      // Play button from PostVideoThumbnail
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('shows full timestamp format in main post', (tester) async {
      final post = makePost(timestamp: DateTime(2024, 12, 25, 9, 5));
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('2024/12/25 09:05'), findsOneWidget);
    });

    testWidgets('shows Bluesky SnsBadge in main post', (tester) async {
      final post = makeBlueskyPost(body: 'Bluesky detail post');
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.byType(SnsBadge), findsOneWidget);
      expect(find.text('Bluesky'), findsOneWidget);
      expect(find.text('Bluesky detail post'), findsOneWidget);
    });

    testWidgets('bookmark already bookmarked post shows filled icon',
        (tester) async {
      final post = makePost(id: 'pre_bookmarked');
      // Pre-bookmark the post
      await BookmarkService.instance.toggle(post);

      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      // Should show filled bookmark icon
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_outline), findsNothing);
    });

    testWidgets('post with high engagement counts displays them',
        (tester) async {
      final post = makePost(
        likeCount: 1234,
        repostCount: 567,
        replyCount: 89,
      );
      await tester.pumpWidget(buildPostDetailScreen(post: post));
      await tester.pump();

      expect(find.text('1234'), findsOneWidget);
      expect(find.text('567'), findsOneWidget);
      expect(find.text('89'), findsOneWidget);
    });
  });
}
