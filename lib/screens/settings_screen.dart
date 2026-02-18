import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('タイムライン取得'),
            subtitle: Text(settings.isFetchingActive ? '実行中' : '停止中'),
            value: settings.isFetchingActive,
            onChanged: (_) => notifier.toggleFetching(),
          ),
          const Divider(),
          ListTile(
            title: const Text('フェッチ間隔'),
            subtitle: Text('${settings.fetchIntervalSeconds} 秒'),
            trailing: DropdownButton<int>(
              value: settings.fetchIntervalSeconds,
              items: const [
                DropdownMenuItem(value: 30, child: Text('30秒')),
                DropdownMenuItem(value: 60, child: Text('60秒')),
                DropdownMenuItem(value: 120, child: Text('2分')),
                DropdownMenuItem(value: 300, child: Text('5分')),
              ],
              onChanged: (value) {
                if (value != null) notifier.setInterval(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}
