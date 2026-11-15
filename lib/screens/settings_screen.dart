import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import 'settings/about_settings_screen.dart';
import 'settings/appearance_settings_screen.dart';
import 'settings/button_layout_settings_screen.dart';
import 'settings/debug_settings_screen.dart';
import 'settings/general_settings_screen.dart';
import 'settings/post_display_settings_screen.dart';
import 'settings/settings_common.dart';
import 'settings/timeline_settings_screen.dart';

/// 設定トップ。操作系は置かず、各詳細画面への入口だけを大きなタイルで並べる。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debugUnlocked = ref.watch(debugUnlockedProvider);

    return settingsScaffold(
      title: '設定',
      body: SettingsNavGrid(
        children: [
          SettingsNavTile(
            icon: Icons.palette_outlined,
            title: '外観',
            builder: (_) => const AppearanceSettingsScreen(),
          ),
          SettingsNavTile(
            icon: Icons.article_outlined,
            title: '投稿の表示',
            builder: (_) => const PostDisplaySettingsScreen(),
          ),
          SettingsNavTile(
            icon: Icons.timer_outlined,
            title: 'タイムライン',
            builder: (_) => const TimelineSettingsScreen(),
          ),
          SettingsNavTile(
            icon: Icons.swap_horiz,
            title: 'ボタン配置',
            builder: (_) => const ButtonLayoutSettingsScreen(),
          ),
          SettingsNavTile(
            icon: Icons.settings_outlined,
            title: '一般',
            builder: (_) => const GeneralSettingsScreen(),
          ),
          SettingsNavTile(
            icon: Icons.info_outline,
            title: 'アプリ情報',
            builder: (_) => const AboutSettingsScreen(),
          ),
          if (debugUnlocked)
            SettingsNavTile(
              icon: Icons.bug_report_outlined,
              title: 'デバッグ',
              builder: (_) => const DebugSettingsScreen(),
            ),
        ],
      ),
    );
  }
}
