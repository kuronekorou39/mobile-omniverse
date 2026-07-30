import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import 'settings_common.dart';

/// ボタン配置設定（ヘッダーバーに出すボタン / 投稿ボタンの左右）
class ButtonLayoutSettingsScreen extends ConsumerWidget {
  const ButtonLayoutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('ボタン配置')),
      body: ListView(
        children: [
          const SettingsSectionHeader(
              title: 'ヘッダーバー', subtitle: 'ヘッダーに表示するボタン'),
          SwitchListTile(
            secondary: const Icon(Icons.timer_outlined),
            title: const Text('フェッチタイマー'),
            value: settings.showFetchTimer,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              notifier.setShowFetchTimer(value);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('匿名切替'),
            value: settings.appBarButtons.contains('userInfo'),
            onChanged: (_) {
              HapticFeedback.selectionClick();
              notifier.toggleAppBarButton('userInfo');
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.screen_lock_portrait_outlined),
            title: const Text('スリープ防止'),
            value: settings.appBarButtons.contains('wakelock'),
            onChanged: (_) {
              HapticFeedback.selectionClick();
              notifier.toggleAppBarButton('wakelock');
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.shield_outlined),
            title: const Text('センシティブ切替'),
            value: settings.appBarButtons.contains('sensitive'),
            onChanged: (_) {
              HapticFeedback.selectionClick();
              notifier.toggleAppBarButton('sensitive');
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.repeat),
            title: const Text('RT非表示切替'),
            value: settings.appBarButtons.contains('retweet'),
            onChanged: (_) {
              HapticFeedback.selectionClick();
              notifier.toggleAppBarButton('retweet');
            },
          ),

          const SettingsSectionGap(),

          const SettingsSectionHeader(title: '投稿ボタン'),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('ボタン位置'),
            trailing: SegmentedButton<FabPosition>(
              showSelectedIcon: false,
              segments: [
                // enum の宣言順（right, left）ではなく画面上の並びに合わせる
                for (final position in [FabPosition.left, FabPosition.right])
                  ButtonSegment(
                    value: position,
                    label: Text(fabPositionLabel(position)),
                  ),
              ],
              selected: {settings.fabPosition},
              onSelectionChanged: (value) =>
                  notifier.setFabPosition(value.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
