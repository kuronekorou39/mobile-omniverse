import 'dart:async';
import 'dart:ui';

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
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AccountStorageService.instance.load();
    await XBearerTokenService.instance.init();
    await XQueryIdService.instance.init();
    await XFeaturesService.instance.init();
    await DebugLogService.instance.init();
    await NotificationCacheService.instance.loadSeenAt();
    MemoryGuardService.instance.start();

    // 未処理例外をクラッシュログとして記録（enabled 非依存）
    FlutterError.onError = (details) {
      DebugLogService.instance.logCrash('FlutterError', details.exception, details.stack);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      DebugLogService.instance.logCrash('DartError', error, stack);
      return true;
    };

    runApp(const ProviderScope(child: OmniVerseApp()));
  }, (error, stack) {
    DebugLogService.instance.logCrash('ZoneError', error, stack);
  });
}

class OmniVerseApp extends ConsumerWidget {
  const OmniVerseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    // Material 3 はデフォルトで AppBar / Card / BottomAppBar 等に primary 由来の
    // surface tint が乗る。スクロール時に AppBar 全体が紫っぽく染まって、通知
    // ハイライトと紛らわしいので、ColorScheme.surfaceTint 自体を透明にして
    // tint を全面的に無効化する。Material 3 の elevation overlay は使わない方針。
    const appBarTheme = AppBarTheme(
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    );
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    ).copyWith(surfaceTint: Colors.transparent);
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    ).copyWith(surfaceTint: Colors.transparent);
    final baseLight = ThemeData(
      colorScheme: lightScheme,
      useMaterial3: true,
      appBarTheme: appBarTheme,
    );
    final baseDark = ThemeData(
      colorScheme: darkScheme,
      useMaterial3: true,
      appBarTheme: appBarTheme,
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
