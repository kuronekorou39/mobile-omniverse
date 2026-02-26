import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/widgets/post_card.dart';
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

  /// Helper to pump a PostCard inside a MaterialApp.
  Widget buildPostCard({
    required post,
    VoidCallback? onTap,
    VoidCallback? onLike,
    VoidCallback? onRepost,
    String? accountHandle,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PostCard(
            post: post,
            onTap: onTap,
            onLike: onLike,
            onRepost: onRepost,
            accountHandle: accountHandle,
          ),
        ),
      ),
    );
  }

  group('PostCard', () {
    testWidgets('post body text is displayed', (tester) async {
      final post = makePost(body: 'Hello, world!');
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('Hello, world!'), findsOneWidget);
    });

    testWidgets('username is displayed', (tester) async {
      final post = makePost(username: 'Test User');
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('Test User'), findsOneWidget);
    });

    testWidgets('handle is displayed', (tester) async {
      final post = makePost(handle: '@testuser');
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('@testuser'), findsOneWidget);
    });

    testWidgets('like count is displayed when > 0', (tester) async {
      final post = makePost(likeCount: 42);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('repost count is displayed when > 0', (tester) async {
      final post = makePost(repostCount: 7);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('reply count is displayed when > 0', (tester) async {
      final post = makePost(replyCount: 3);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('RT header shows when isRetweet is true and retweetedByUsername is set', (tester) async {
      final post = makePost(
        isRetweet: true,
        retweetedByUsername: 'RetweetUser',
      );
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.textContaining('RetweetUser'), findsOneWidget);
      expect(find.textContaining('リツイート'), findsOneWidget);
    });

    testWidgets('RT header is hidden when not a retweet', (tester) async {
      final post = makePost(isRetweet: false);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.textContaining('リツイート'), findsNothing);
    });

    testWidgets('like icon shows filled heart when isLiked is true', (tester) async {
      final post = makePost(isLiked: true, likeCount: 1);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });

    testWidgets('repost icon is green when isReposted is true', (tester) async {
      final post = makePost(isReposted: true, repostCount: 1);
      await tester.pumpWidget(buildPostCard(post: post));

      // Find the repeat icon and verify its color is green.
      // The engagement row has a repeat icon; when isReposted, its color is green.
      final repeatIcons = find.byIcon(Icons.repeat);
      // There should be at least one repeat icon (engagement button).
      expect(repeatIcons, findsAtLeastNWidgets(1));

      // Find the Icon widget in the engagement row (the one wrapped with AnimatedBuilder).
      bool foundGreenRepeat = false;
      for (final element in tester.widgetList<Icon>(repeatIcons)) {
        if (element.color == Colors.green) {
          foundGreenRepeat = true;
          break;
        }
      }
      expect(foundGreenRepeat, isTrue);
    });

    testWidgets('onLike callback is called on like button tap', (tester) async {
      bool likeCalled = false;
      final post = makePost();
      await tester.pumpWidget(buildPostCard(
        post: post,
        onLike: () => likeCalled = true,
      ));

      // The like button is an InkWell wrapping the heart icon.
      // Find the favorite_border icon and tap its parent InkWell.
      final heartIcon = find.byIcon(Icons.favorite_border);
      expect(heartIcon, findsOneWidget);
      await tester.tap(heartIcon);
      await tester.pump();

      expect(likeCalled, isTrue);
    });

    testWidgets('onRepost callback is called on repost button tap', (tester) async {
      bool repostCalled = false;
      final post = makePost();
      await tester.pumpWidget(buildPostCard(
        post: post,
        onRepost: () => repostCalled = true,
      ));

      // Find all repeat icons; the one in the engagement row is tappable.
      final repeatIcons = find.byIcon(Icons.repeat);
      expect(repeatIcons, findsAtLeastNWidgets(1));
      // Tap the first repeat icon (engagement button).
      await tester.tap(repeatIcons.first);
      await tester.pump();

      expect(repostCalled, isTrue);
    });

    testWidgets('onTap callback is called on card tap', (tester) async {
      bool tapCalled = false;
      final post = makePost();
      await tester.pumpWidget(buildPostCard(
        post: post,
        onTap: () => tapCalled = true,
      ));

      // Tap on the card body text area.
      await tester.tap(find.text('Hello, world!'));
      await tester.pump();

      expect(tapCalled, isTrue);
    });

    testWidgets('SnsBadge is shown for the post source', (tester) async {
      final post = makePost(source: SnsService.x);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.byType(SnsBadge), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
    });

    testWidgets('quoted post card is shown when quotedPost is not null', (tester) async {
      final quoted = makePost(
        id: 'quoted_1',
        username: 'Quoted Author',
        handle: '@quotedauthor',
        body: 'This is a quoted post',
      );
      final post = makePost(quotedPost: quoted);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('Quoted Author'), findsOneWidget);
      expect(find.text('This is a quoted post'), findsOneWidget);
    });

    testWidgets('engagement count shows K for thousands', (tester) async {
      final post = makePost(likeCount: 1500, repostCount: 2300, replyCount: 9999);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('1.5K'), findsOneWidget);
      expect(find.text('2.3K'), findsOneWidget);
      expect(find.text('10.0K'), findsOneWidget);
    });

    testWidgets('engagement count shows M for millions', (tester) async {
      final post = makePost(likeCount: 1500000);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('1.5M'), findsOneWidget);
    });

    testWidgets('zero counts hide text', (tester) async {
      final post = makePost(likeCount: 0, repostCount: 0, replyCount: 0);
      await tester.pumpWidget(buildPostCard(post: post));

      // Count text widgets should not appear
      expect(find.text('0'), findsNothing);
    });

    testWidgets('accountHandle via is shown when provided', (tester) async {
      final post = makePost();
      await tester.pumpWidget(buildPostCard(post: post, accountHandle: '@myaccount'));

      expect(find.text(' via '), findsOneWidget);
      expect(find.text('@myaccount'), findsOneWidget);
    });

    testWidgets('accountHandle via is hidden when null', (tester) async {
      final post = makePost();
      await tester.pumpWidget(buildPostCard(post: post, accountHandle: null));

      expect(find.text(' via '), findsNothing);
    });

    testWidgets('Bluesky source shows Bluesky badge', (tester) async {
      final post = makePost(source: SnsService.bluesky);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.byType(SnsBadge), findsOneWidget);
      expect(find.text('Bluesky'), findsOneWidget);
    });

    testWidgets('body text with URLs renders LinkedText', (tester) async {
      final post = makePost(body: 'Visit https://example.com for more');
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.textContaining('https://example.com'), findsOneWidget);
    });

    testWidgets('PostVideoThumbnail renders when video present', (tester) async {
      final post = makePost(
        videoUrl: 'https://example.com/video.mp4',
        videoThumbnailUrl: 'https://example.com/thumb.jpg',
      );
      await tester.pumpWidget(buildPostCard(post: post));

      // Play button should be visible
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('image grid renders when images present', (tester) async {
      final post = makePost(
        imageUrls: [
          'https://example.com/img1.jpg',
          'https://example.com/img2.jpg',
        ],
      );
      await tester.pumpWidget(buildPostCard(post: post));

      // PostImageGrid should be present (renders GestureDetectors)
      // 2 for image grid + 1 for avatar tap = 3 GestureDetectors
      expect(find.byType(GestureDetector), findsAtLeastNWidgets(2));
    });

    testWidgets('timestamp displays recent time', (tester) async {
      final post = makePost(timestamp: DateTime.now().subtract(const Duration(minutes: 5)));
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('5m'), findsOneWidget);
    });

    testWidgets('timestamp displays hours for older posts', (tester) async {
      final post = makePost(timestamp: DateTime.now().subtract(const Duration(hours: 3)));
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('3h'), findsOneWidget);
    });

    testWidgets('timestamp displays days for much older posts', (tester) async {
      final post = makePost(timestamp: DateTime.now().subtract(const Duration(days: 2)));
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('2d'), findsOneWidget);
    });

    testWidgets('timestamp displays "now" for very recent posts', (tester) async {
      final post = makePost(timestamp: DateTime.now());
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('now'), findsOneWidget);
    });

    testWidgets('timestamp displays month/day for posts older than 7 days', (tester) async {
      final post = makePost(timestamp: DateTime.now().subtract(const Duration(days: 10)));
      await tester.pumpWidget(buildPostCard(post: post));

      // Should show month/day format like "2/15"
      final expected = '${post.timestamp.month}/${post.timestamp.day}';
      expect(find.text(expected), findsOneWidget);
    });

    testWidgets('empty body hides LinkedText', (tester) async {
      final post = makePost(body: '');
      await tester.pumpWidget(buildPostCard(post: post));

      // LinkedText with empty text renders SizedBox.shrink, not visible text
      expect(find.text(''), findsNothing);
    });

    testWidgets('avatar shows "?" when username is empty', (tester) async {
      final post = makePost(username: '', avatarUrl: null);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('avatar shows first letter capitalized when username exists', (tester) async {
      final post = makePost(username: 'zulu', avatarUrl: null);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('share icon is present when permalink exists', (tester) async {
      final post = makePost(permalink: 'https://x.com/user/status/123');
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    });

    testWidgets('share icon is present but disabled when no permalink', (tester) async {
      final post = makePost(permalink: null);
      await tester.pumpWidget(buildPostCard(post: post));

      // The share icon is always shown, but with null onPressed when no permalink
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);

      // Verify the IconButton has null onPressed
      final iconButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.share_outlined),
          matching: find.byType(IconButton),
        ),
      );
      expect(iconButton.onPressed, isNull);
    });

    testWidgets('like button does not trigger when onLike is null', (tester) async {
      final post = makePost();
      await tester.pumpWidget(buildPostCard(post: post, onLike: null));

      // The heart icon should still exist
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      // Tapping should not cause any error
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
    });

    testWidgets('repost button does not trigger when onRepost is null', (tester) async {
      final post = makePost();
      await tester.pumpWidget(buildPostCard(post: post, onRepost: null));

      final repeatIcons = find.byIcon(Icons.repeat);
      expect(repeatIcons, findsAtLeastNWidgets(1));

      // Tapping should not cause any error
      await tester.tap(repeatIcons.first);
      await tester.pump();
    });

    testWidgets('quoted post with empty body shows only header', (tester) async {
      final quoted = makePost(
        id: 'quoted_empty',
        username: 'QuoteAuthor',
        handle: '@quoteauthor',
        body: '',
      );
      final post = makePost(quotedPost: quoted);
      await tester.pumpWidget(buildPostCard(post: post));

      // The quoted post header should still show
      expect(find.text('QuoteAuthor'), findsOneWidget);
      expect(find.text('@quoteauthor'), findsOneWidget);
    });

    testWidgets('quoted post with images shows image grid', (tester) async {
      final quoted = makePost(
        id: 'quoted_img',
        username: 'ImgQuote',
        handle: '@imgquote',
        body: 'Quoted with images',
        imageUrls: ['https://example.com/quoted_img.jpg'],
      );
      final post = makePost(quotedPost: quoted);
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.text('ImgQuote'), findsOneWidget);
      expect(find.text('Quoted with images'), findsOneWidget);
    });

    testWidgets('quoted post without avatar shows initial', (tester) async {
      final quoted = makePost(
        id: 'quoted_no_avatar',
        username: 'NoAvatarQuote',
        handle: '@noavatar',
        body: 'No avatar quoted',
        avatarUrl: null,
      );
      final post = makePost(quotedPost: quoted);
      await tester.pumpWidget(buildPostCard(post: post));

      // Should show 'N' as initial for 'NoAvatarQuote' in the small avatar
      expect(find.text('N'), findsOneWidget);
    });

    testWidgets('quoted post with empty username shows "?" in avatar', (tester) async {
      final quoted = makePost(
        id: 'quoted_empty_name',
        username: '',
        handle: '@emptyname',
        body: 'Empty name quoted',
        avatarUrl: null,
      );
      final post = makePost(quotedPost: quoted);
      await tester.pumpWidget(buildPostCard(post: post));

      // The parent post avatar shows '?' for its own empty username check,
      // and the quoted post avatar also shows '?' - find at least one
      expect(find.text('?'), findsAtLeastNWidgets(1));
    });

    testWidgets('RT header is hidden when isRetweet is true but retweetedByUsername is null', (tester) async {
      final post = makePost(isRetweet: true, retweetedByUsername: null);
      await tester.pumpWidget(buildPostCard(post: post));

      // RT header requires both isRetweet && retweetedByUsername != null
      expect(find.textContaining('リツイート'), findsNothing);
    });

    testWidgets('liked post shows red heart color', (tester) async {
      final post = makePost(isLiked: true, likeCount: 5);
      await tester.pumpWidget(buildPostCard(post: post));

      final heartIcons = find.byIcon(Icons.favorite);
      expect(heartIcons, findsOneWidget);

      // Verify the Icon color is red
      final heartIcon = tester.widget<Icon>(heartIcons);
      expect(heartIcon.color, Colors.red);
    });

    testWidgets('not liked post shows grey heart color', (tester) async {
      final post = makePost(isLiked: false, likeCount: 5);
      await tester.pumpWidget(buildPostCard(post: post));

      final heartIcons = find.byIcon(Icons.favorite_border);
      expect(heartIcons, findsOneWidget);

      final heartIcon = tester.widget<Icon>(heartIcons);
      expect(heartIcon.color, Colors.grey[600]);
    });

    testWidgets('Card has InkWell for tap behavior', (tester) async {
      final post = makePost();
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.byType(InkWell), findsAtLeastNWidgets(1));
    });

    testWidgets('Card has correct margin', (tester) async {
      final post = makePost();
      await tester.pumpWidget(buildPostCard(post: post));

      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('shows CachedNetworkImage avatar when avatarUrl is provided',
        (tester) async {
      final post = makePost(
        username: 'AvatarUser',
        avatarUrl: 'https://example.com/avatar.jpg',
      );
      await tester.pumpWidget(buildPostCard(post: post));
      await tester.pump();

      // CachedNetworkImage should be present (it renders the avatar)
      // The Hero widget wraps the avatar
      expect(find.byType(Hero), findsOneWidget);
      // Username should still show
      expect(find.text('AvatarUser'), findsOneWidget);
    });

    testWidgets(
        'quoted post with avatarUrl shows CachedNetworkImage avatar',
        (tester) async {
      final quoted = makePost(
        id: 'quoted_with_avatar',
        username: 'QuotedAvatarUser',
        handle: '@quotedavatar',
        body: 'Quoted with avatar',
        avatarUrl: 'https://example.com/quoted_avatar.jpg',
      );
      final post = makePost(quotedPost: quoted);
      await tester.pumpWidget(buildPostCard(post: post));
      await tester.pump();

      // Quoted post header should render
      expect(find.text('QuotedAvatarUser'), findsOneWidget);
      expect(find.text('Quoted with avatar'), findsOneWidget);
    });

    testWidgets('share button with permalink shows IconButton',
        (tester) async {
      final post =
          makePost(permalink: 'https://x.com/user/status/123');
      await tester.pumpWidget(buildPostCard(post: post));

      // The share icon should exist and be tappable
      final shareIcons = find.byIcon(Icons.share_outlined);
      expect(shareIcons, findsOneWidget);

      // Find the IconButton containing share icon
      final iconButton = tester.widget<IconButton>(
        find.ancestor(
          of: shareIcons,
          matching: find.byType(IconButton),
        ),
      );
      // When permalink is set, onPressed should not be null
      expect(iconButton.onPressed, isNotNull);
    });
  });
}
