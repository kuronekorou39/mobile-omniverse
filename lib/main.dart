import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/settings_provider.dart';
import 'screens/overlay_timeline_screen.dart';
import 'widgets/perf_overlay.dart';
import 'screens/splash_screen.dart';
import 'services/account_storage_service.dart';
import 'services/debug_log_service.dart';
import 'services/memory_guard_service.dart';
import 'services/notification_cache_service.dart';
import 'services/x_bearer_token_service.dart';
import 'services/x_features_service.dart';
import 'services/x_query_id_service.dart';

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayTimelineScreen(),
  ));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AccountStorageService.instance.load();
  await XBearerTokenService.instance.init();
  await XQueryIdService.instance.init();
  await XFeaturesService.instance.init();
  await DebugLogService.instance.init();
  await NotificationCacheService.instance.loadReadLines();
  MemoryGuardService.instance.start();
  runApp(const ProviderScope(child: OmniVerseApp()));
}

class OmniVerseApp extends ConsumerWidget {
  const OmniVerseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    final baseLight = ThemeData(
      colorSchemeSeed: const Color(0xFF6750A4),
      useMaterial3: true,
      brightness: Brightness.light,
    );
    final baseDark = ThemeData(
      colorSchemeSeed: const Color(0xFF6750A4),
      useMaterial3: true,
      brightness: Brightness.dark,
    );

    final fontFamily = settings.fontFamily;
    final lightTheme = fontFamily.isEmpty
        ? baseLight
        : baseLight.copyWith(
            textTheme: GoogleFonts.getTextTheme(fontFamily, baseLight.textTheme),
          );
    final darkTheme = fontFamily.isEmpty
        ? baseDark
        : baseDark.copyWith(
            textTheme: GoogleFonts.getTextTheme(fontFamily, baseDark.textTheme),
          );

    return MaterialApp(
      title: 'OmniVerse',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(settings.fontScale),
          ),
          child: Stack(
            children: [
              child!,
              if (settings.showPerfOverlay) const PerfOverlay(),
            ],
          ),
        );
      },
      home: const SplashScreen(),
    );
  }
}
