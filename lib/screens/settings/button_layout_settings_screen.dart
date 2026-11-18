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

    return settingsScaffold(
      title: 'ボタン配置',
      body: LayoutBuilder(builder: (context, constraints) {
        final switches = <Widget>[
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
          SwitchListTile(
            secondary: const Icon(Icons.chat_bubble_outline),
            title: const Text('アクション非表示切替'),
            subtitle: const Text('タイムラインの返信・RT・いいねの行を隠す'),
            value: settings.appBarButtons.contains('engagement'),
            onChanged: (_) {
              HapticFeedback.selectionClick();
              notifier.toggleAppBarButton('engagement');
            },
          ),
        ];
        Widget fabTile(String title) => ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(title),
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
          );
        const headerSection = SettingsSectionHeader(
            title: 'ヘッダーバー', subtitle: 'ヘッダーに表示するボタン');

        // 横向きは縦が足りず、横に長い行では項目名とスイッチが離れすぎる。
        // スイッチを 2 列に組み、投稿ボタンは見出しを省いて 1 行で下に置く
        final side = constraints.maxWidth > constraints.maxHeight &&
            constraints.maxWidth >= 600;
        if (!side) {
          return ListView(
            children: [
              headerSection,
              ...switches,
              const SettingsSectionGap(),
              const SettingsSectionHeader(title: '投稿ボタン'),
              fabTile('ボタン位置'),
            ],
          );
        }
        Widget pair(Widget left, Widget? right) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                Expanded(child: right ?? const SizedBox.shrink()),
              ],
            );
        return SingleChildScrollView(
          child: Column(
            children: [
              headerSection,
              for (var i = 0; i < switches.length; i += 2)
                pair(switches[i],
                    i + 1 < switches.length ? switches[i + 1] : null),
              const SettingsSectionGap(),
              pair(fabTile('投稿ボタンの位置'), null),
            ],
          ),
        );
      }),
    );
  }
}
