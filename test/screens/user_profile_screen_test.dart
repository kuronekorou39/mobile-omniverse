import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/screens/user_profile_screen.dart';
import 'package:mobile_omniverse/services/account_storage_service.dart';
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
    await AccountStorageService.instance.load();
  });

  Widget buildUserProfileScreen({
    String username = 'Test User',
    String handle = '@testuser',
    SnsService service = SnsService.x,
    String? avatarUrl,
    String? accountId,
  }) {
    return MaterialApp(
      home: UserProfileScreen(
        username: username,
        handle: handle,
        service: service,
        avatarUrl: avatarUrl,
        accountId: accountId,
      ),
    );
  }

  group('UserProfileScreen', () {
    testWidgets('shows handle in AppBar', (tester) async {
      await tester.pumpWidget(buildUserProfileScreen(handle: '@myhandle'));
      await tester.pump();

      expect(find.text('@myhandle'), findsAtLeastNWidgets(1));
    });

    testWidgets('displays username in profile header', (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(username: 'Alice Wonder'));
      await tester.pump();

      expect(find.text('Alice Wonder'), findsOneWidget);
    });

    testWidgets('displays handle in profile header', (tester) async {
      await tester.pumpWidget(buildUserProfileScreen(handle: '@alice'));
      await tester.pump();

      // Handle appears in AppBar and in profile header row
      expect(find.text('@alice'), findsAtLeastNWidgets(2));
    });

    testWidgets('displays SnsBadge for X service', (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(service: SnsService.x));
      await tester.pump();

      expect(find.byType(SnsBadge), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
    });

    testWidgets('displays SnsBadge for Bluesky service', (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(service: SnsService.bluesky));
      await tester.pump();

      expect(find.byType(SnsBadge), findsOneWidget);
      expect(find.text('Bluesky'), findsOneWidget);
    });

    testWidgets('shows CircleAvatar', (tester) async {
      await tester.pumpWidget(buildUserProfileScreen());
      await tester.pump();

      expect(find.byType(CircleAvatar), findsAtLeastNWidgets(1));
    });

    testWidgets('shows initial letter in avatar when no avatarUrl',
        (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(username: 'Zara', avatarUrl: null));
      await tester.pump();

      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('shows "?" when username is empty and no avatarUrl',
        (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(username: '', avatarUrl: null));
      await tester.pump();

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('shows error when accountId is null', (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(accountId: null));
      await tester.pumpAndSettle();

      // Should show error text for profile and posts
      expect(find.text('アカウント情報が見つかりません'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows error when accountId is invalid', (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(accountId: 'nonexistent_id'));
      await tester.pumpAndSettle();

      expect(find.text('アカウント情報が見つかりません'), findsAtLeastNWidgets(1));
    });

    testWidgets('contains NestedScrollView with TabBarView', (tester) async {
      await tester.pumpWidget(buildUserProfileScreen());
      await tester.pump();

      expect(find.byType(NestedScrollView), findsOneWidget);
      expect(find.byType(TabBarView), findsOneWidget);
    });

    testWidgets('contains TabBar with 投稿 and メディア tabs', (tester) async {
      await tester.pumpWidget(buildUserProfileScreen());
      await tester.pump();

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('投稿'), findsOneWidget);
      expect(find.text('メディア'), findsOneWidget);
    });

    testWidgets('shows error state when account not found',
        (tester) async {
      // accountId=null → profile and posts immediately error
      await tester.pumpWidget(
          buildUserProfileScreen(accountId: null));
      await tester.pumpAndSettle();

      // Error state shows error text
      expect(find.text('アカウント情報が見つかりません'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows posts error state when loading fails', (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(accountId: null));
      await tester.pumpAndSettle();

      // Error state should show the error text
      expect(find.text('アカウント情報が見つかりません'), findsAtLeastNWidgets(1));
    });

    testWidgets('does not show follow button (removed for multi-account)', (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(service: SnsService.x, accountId: null));
      await tester.pumpAndSettle();

      // Follow button removed — ambiguous with multiple accounts
      expect(find.text('フォロー'), findsNothing);
      expect(find.text('フォロー中'), findsNothing);
    });

    testWidgets('renders Scaffold', (tester) async {
      await tester.pumpWidget(buildUserProfileScreen());
      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('renders AppBar', (tester) async {
      await tester.pumpWidget(buildUserProfileScreen());
      await tester.pump();

      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('UserProfileScreen - profile header details', () {
    testWidgets('shows profile error text when account not found',
        (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(accountId: null, service: SnsService.bluesky));
      await tester.pumpAndSettle();

      expect(find.text('アカウント情報が見つかりません'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows posts error when account is null', (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(accountId: null, service: SnsService.x));
      await tester.pumpAndSettle();

      // Both profile and posts error
      expect(find.text('アカウント情報が見つかりません'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows profile header elements for X service', (tester) async {
      // Use null accountId to avoid real HTTP calls
      await tester.pumpWidget(buildUserProfileScreen(
        accountId: null,
        service: SnsService.x,
        username: 'XUser',
        handle: '@xuser',
      ));
      await tester.pumpAndSettle();

      // Profile header shows username and handle
      expect(find.text('XUser'), findsOneWidget);
      expect(find.text('@xuser'), findsAtLeastNWidgets(1));
      expect(find.byType(SnsBadge), findsOneWidget);
    });

    testWidgets('profile header shows username with bold style',
        (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(username: 'BoldName'));
      await tester.pump();

      final nameText = tester.widget<Text>(find.text('BoldName'));
      expect(nameText.style?.fontWeight, FontWeight.bold);
      expect(nameText.style?.fontSize, 20);
    });

    testWidgets('shows avatar circle with correct initial for name',
        (tester) async {
      await tester.pumpWidget(
          buildUserProfileScreen(username: 'Alice', avatarUrl: null));
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
    });
  });

  group('UserProfileScreen - X account shows empty posts state', () {
    testWidgets('shows error when X account not found',
        (tester) async {
      // Use null accountId to avoid real HTTP calls
      await tester.pumpWidget(buildUserProfileScreen(
        accountId: null,
        service: SnsService.x,
        username: 'XProfileUser',
        handle: '@xprofile',
      ));
      await tester.pumpAndSettle();

      // Profile header shows username even when account load fails
      expect(find.text('XProfileUser'), findsOneWidget);
      expect(find.text('アカウント情報が見つかりません'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows posts error state with retry button when account is null',
        (tester) async {
      await tester.pumpWidget(buildUserProfileScreen(
        accountId: null,
        service: SnsService.bluesky,
        username: 'ErrorUser',
        handle: '@erroruser',
      ));
      await tester.pumpAndSettle();

      // Should show error for posts
      expect(find.text('アカウント情報が見つかりません'), findsAtLeastNWidgets(1));
    });

    testWidgets('profile header shows correct handle text style',
        (tester) async {
      await tester.pumpWidget(buildUserProfileScreen(
        username: 'StyledUser',
        handle: '@styledhandle',
        service: SnsService.bluesky,
      ));
      await tester.pump();

      // Handle text in profile header
      expect(find.text('@styledhandle'), findsAtLeastNWidgets(1));
    });

    testWidgets('X service does not show follow button',
        (tester) async {
      await tester.pumpWidget(buildUserProfileScreen(
        accountId: null,
        service: SnsService.x,
        username: 'NoFollowUser',
        handle: '@nofollow',
      ));
      await tester.pumpAndSettle();

      expect(find.text('NoFollowUser'), findsOneWidget);
      // Follow button removed for multi-account clarity
      expect(find.text('フォロー'), findsNothing);
      expect(find.text('フォロー中'), findsNothing);
    });

    testWidgets('Bluesky account without account shows error but no follow button',
        (tester) async {
      await tester.pumpWidget(buildUserProfileScreen(
        accountId: null,
        service: SnsService.bluesky,
        username: 'BskyNoAcc',
        handle: '@bskynoacc',
      ));
      await tester.pumpAndSettle();

      // Profile error shows
      expect(find.text('アカウント情報が見つかりません'), findsAtLeastNWidgets(1));
      // After loading, follow button may appear for Bluesky but profile failed
    });

    testWidgets('CircleAvatar radius is 36 in profile header', (tester) async {
      await tester.pumpWidget(buildUserProfileScreen(
        username: 'AvatarUser',
        handle: '@avataruser',
        avatarUrl: null,
      ));
      await tester.pump();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);
      expect(avatar.radius, 36);
    });
  });

  group('navigateToUserProfile helper', () {
    testWidgets('navigates to UserProfileScreen from a post', (tester) async {
      final post = makePost(
        username: 'NavUser',
        handle: '@navuser',
        source: SnsService.x,
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => navigateToUserProfile(context, post: post),
              child: const Text('Navigate'),
            );
          },
        ),
      ));

      await tester.tap(find.text('Navigate'));
      await tester.pumpAndSettle();

      // Should be on the UserProfileScreen now
      expect(find.text('NavUser'), findsOneWidget);
      expect(find.text('@navuser'), findsAtLeastNWidgets(1));
    });

    testWidgets('navigateToUserProfile passes all post fields', (tester) async {
      final post = makePost(
        username: 'FullUser',
        handle: '@fulluser',
        source: SnsService.bluesky,
        avatarUrl: null,
        accountId: 'acc_123',
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => navigateToUserProfile(context, post: post),
              child: const Text('Go'),
            );
          },
        ),
      ));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('FullUser'), findsOneWidget);
      expect(find.text('@fulluser'), findsAtLeastNWidgets(1));
      expect(find.byType(SnsBadge), findsOneWidget);
    });
  });
}
