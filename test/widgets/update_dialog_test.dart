import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_omniverse/services/app_update_service.dart';
import 'package:mobile_omniverse/widgets/update_dialog.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('showUpdateDialog', () {
    testWidgets('displays dialog title "アップデートがあります"', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            // Schedule showing the dialog after frame completes
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showUpdateDialog(
                context,
                const AppUpdateInfo(
                  currentVersion: '1.0.0',
                  latestVersion: '1.1.0',
                  releaseNotes: '',
                  releaseUrl: 'https://github.com/test/releases',
                ),
              );
            });
            return const Scaffold();
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('アップデートがあります'), findsOneWidget);
    });

    testWidgets('displays version transition text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showUpdateDialog(
                context,
                const AppUpdateInfo(
                  currentVersion: '1.0.0',
                  latestVersion: '2.0.0',
                  releaseNotes: '',
                  releaseUrl: 'https://github.com/test/releases',
                ),
              );
            });
            return const Scaffold();
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('v1.0.0 → v2.0.0'), findsOneWidget);
    });

    testWidgets('displays release notes when present', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showUpdateDialog(
                context,
                const AppUpdateInfo(
                  currentVersion: '1.0.0',
                  latestVersion: '1.1.0',
                  releaseNotes: 'Bug fixes and performance improvements',
                  releaseUrl: 'https://github.com/test/releases',
                ),
              );
            });
            return const Scaffold();
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('リリースノート:'), findsOneWidget);
      expect(
          find.text('Bug fixes and performance improvements'), findsOneWidget);
    });

    testWidgets('hides release notes label when notes are empty',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showUpdateDialog(
                context,
                const AppUpdateInfo(
                  currentVersion: '1.0.0',
                  latestVersion: '1.1.0',
                  releaseNotes: '',
                  releaseUrl: 'https://github.com/test/releases',
                ),
              );
            });
            return const Scaffold();
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('リリースノート:'), findsNothing);
    });

    testWidgets('displays "後で" and "アップデート" buttons', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showUpdateDialog(
                context,
                const AppUpdateInfo(
                  currentVersion: '1.0.0',
                  latestVersion: '1.1.0',
                  releaseNotes: '',
                  releaseUrl: 'https://github.com/test/releases',
                ),
              );
            });
            return const Scaffold();
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('後で'), findsOneWidget);
      expect(find.text('アップデート'), findsOneWidget);
    });

    testWidgets('"後で" button closes the dialog', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showUpdateDialog(
                context,
                const AppUpdateInfo(
                  currentVersion: '1.0.0',
                  latestVersion: '1.1.0',
                  releaseNotes: '',
                  releaseUrl: 'https://github.com/test/releases',
                ),
              );
            });
            return const Scaffold();
          },
        ),
      ));
      await tester.pumpAndSettle();

      // Verify dialog is showing
      expect(find.text('アップデートがあります'), findsOneWidget);

      // Tap "後で"
      await tester.tap(find.text('後で'));
      await tester.pumpAndSettle();

      // Dialog should be closed
      expect(find.text('アップデートがあります'), findsNothing);
    });

    testWidgets('displays as AlertDialog', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showUpdateDialog(
                context,
                const AppUpdateInfo(
                  currentVersion: '1.0.0',
                  latestVersion: '1.1.0',
                  releaseNotes: 'Some notes',
                  releaseUrl: 'https://github.com/test/releases',
                ),
              );
            });
            return const Scaffold();
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
