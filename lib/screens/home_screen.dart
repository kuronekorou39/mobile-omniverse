import 'package:flutter/material.dart';

import '../models/sns_service.dart';
import '../screens/omni_feed_screen.dart';
import '../screens/webview_tab_screen.dart';
import '../screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _pages = [
    const OmniFeedScreen(),
    const WebViewTabScreen(service: SnsService.x),
    const WebViewTabScreen(service: SnsService.bluesky),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OmniVerse'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dynamic_feed),
            label: 'Omni-Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.close),
            label: 'X',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud),
            label: 'Bluesky',
          ),
        ],
      ),
    );
  }
}
