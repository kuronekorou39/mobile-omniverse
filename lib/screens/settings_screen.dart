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

/// 設定トップ。操作系は置かず、各詳細画面への入口だけを並べる。
/// 各行の subtitle に現在値を出して、中に入らなくても設定状態が分かるようにする。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final version = ref.watch(packageVersionProvider).asData?.value;
    final debugUnlocked = ref.watch(debugUnlockedProvider);

    // ヘッダーに出ているボタンの数（フェッチタイマーは appBarButtons とは別管理）
    final headerButtonCount =
        settings.appBarButtons.length + (settings.showFetchTimer ? 1 : 0);
    final fetchInterval = fetchIntervalOptions[settings.fetchIntervalSeconds] ??
        '${settings.fetchIntervalSeconds}秒';
    final dripInterval = dripIntervalOptions[settings.dripIntervalMs] ??
        '${settings.dripIntervalMs}ms';

    return settingsScaffold(
      title: '設定',
      body: ListView(
        children: [
          SettingsNavTile(
            icon: Icons.palette_outlined,
            title: '外観',
            subtitle: '${themeModeLabel(settings.themeMode)}'
                '・${fontFamilyLabel(settings.fontFamily)}',
            builder: (_) => const AppearanceSettingsScreen(),
          ),
          SettingsNavTile(
            icon: Icons.article_outlined,
            title: '投稿の表示',
            subtitle: '${postCardStyleLabel(settings.postCardStyle)}'
                '・画像${settings.imagePreviewSize.label}',
            builder: (_) => const PostDisplaySettingsScreen(),
          ),
          SettingsNavTile(
            icon: Icons.timer_outlined,
            title: 'タイムライン',
            subtitle: '$fetchInterval・ドリップ$dripInterval',
            builder: (_) => const TimelineSettingsScreen(),
          ),
          SettingsNavTile(
            icon: Icons.swap_horiz,
            title: 'ボタン配置',
            subtitle: 'ヘッダー$headerButtonCount個'
                '・投稿ボタン${fabPositionLabel(settings.fabPosition)}',
            builder: (_) => const ButtonLayoutSettingsScreen(),
          ),
          SettingsNavTile(
            icon: Icons.settings_outlined,
            title: '一般',
            subtitle: 'スリープ防止 ${settings.keepScreenOn ? 'ON' : 'OFF'}'
                '・保存先 ${settings.imageSaveFolder}',
            builder: (_) => const GeneralSettingsScreen(),
          ),
          SettingsNavTile(
            icon: Icons.info_outline,
            title: 'アプリ情報',
            subtitle: version == null ? null : 'v$version',
            builder: (_) => const AboutSettingsScreen(),
          ),
          if (debugUnlocked)
            SettingsNavTile(
              icon: Icons.bug_report_outlined,
              title: 'デバッグ',
              subtitle: '開発者向け',
              builder: (_) => const DebugSettingsScreen(),
            ),
        ],
      ),
    );
  }
}
