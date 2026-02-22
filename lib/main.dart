import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/settings_provider.dart';
import 'screens/splash_screen.dart';
import 'services/account_storage_service.dart';
import 'services/x_query_id_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AccountStorageService.instance.load();
  await XQueryIdService.instance.init();
  runApp(const ProviderScope(child: OmniVerseApp()));
}

class OmniVerseApp extends ConsumerWidget {
  const OmniVerseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'OmniVerse',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      builder: (context, child) {
        // Apply font scale from settings
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(settings.fontScale),
          ),
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}
