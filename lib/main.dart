import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';
import 'services/cookie_persistence_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CookiePersistenceService.instance.restoreAll();
  runApp(const ProviderScope(child: OmniVerseApp()));
}

class OmniVerseApp extends StatelessWidget {
  const OmniVerseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniVerse',
      debugShowCheckedModeBanner: false,
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
      home: const HomeScreen(),
    );
  }
}
