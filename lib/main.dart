import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/settings_provider.dart';
import 'screens/overlay_timeline_screen.dart';
import 'widgets/perf_overlay.dart';
import 'screens/splash_screen.dart';
import 'services/account_storage_service.dart';
import 'services/compose_image_store.dart';
import 'services/debug_log_service.dart';
import 'services/draft_service.dart';
import 'services/memory_guard_service.dart';
import 'services/notification_cache_service.dart';
import 'services/x_bearer_token_service.dart';
import 'services/x_features_service.dart';
import 'services/follow_capture_job_service.dart';
import 'services/x_query_id_service.dart';
import 'widgets/follow_capture_webview_host.dart';

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

    // 下書きから参照されていない投稿用画像を片付ける。
    // 下書きと投稿失敗時の再送で使うので、参照が残っているものは消さない。
    unawaited(DraftService.instance.referencedImagePaths().then(
        ComposeImageStore.instance.cleanup));

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

    // 画面遷移の演出を全体で揃える。既定 (Android) は ZoomPageTransitions で、
    // タイムラインが独自に使っている横スライドと印象が食い違うため、
    // MaterialPageRoute 側も横スライドに寄せる。
    const pageTransitions = PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    });

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
      pageTransitionsTheme: pageTransitions,
    );
    final baseDark = ThemeData(
      colorScheme: darkScheme,
      useMaterial3: true,
      appBarTheme: appBarTheme,
      pageTransitionsTheme: pageTransitions,
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
              // 走査中だけルートに WebView を置く。
              // ここに置くことで、取得画面を離れてタイムラインを見ていても
              // 走査が続く（アプリ自体を裏に回すと止まる）。
              Positioned(
                left: FollowCaptureWebViewHost.offscreenX,
                top: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable:
                      FollowCaptureJobService.instance.hostNeeded,
                  builder: (_, needed, __) => needed
                      ? const FollowCaptureWebViewHost()
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
      home: const SplashScreen(),
    );
  }
}
