import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import 'settings_common.dart';

/// タイムライン取得設定（取得間隔 / ドリップ速度 / RT非表示）
class TimelineSettingsScreen extends ConsumerWidget {
  const TimelineSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('タイムライン')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('取得間隔'),
            trailing: DropdownButton<int>(
              value: settings.fetchIntervalSeconds,
              items: [
                for (final entry in fetchIntervalOptions.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: (value) {
                if (value != null) notifier.setInterval(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.water_drop_outlined),
            title: const Text('ドリップ速度'),
            subtitle: const Text('取得した投稿をタイムラインに流す間隔'),
            trailing: DropdownButton<int>(
              value: settings.dripIntervalMs,
              items: [
                for (final entry in dripIntervalOptions.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: (value) {
                if (value != null) notifier.setDripIntervalMs(value);
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.repeat),
            title: const Text('RT / リポストを非表示'),
            value: settings.hideAllRetweets,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              notifier.setHideAllRetweets(value);
            },
          ),
        ],
      ),
    );
  }
}
