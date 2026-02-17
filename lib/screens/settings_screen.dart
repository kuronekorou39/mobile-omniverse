import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sns_service.dart';
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
            title: const Text('スクレイピング'),
            subtitle: Text(settings.isScrapingActive ? '実行中' : '停止中'),
            value: settings.isScrapingActive,
            onChanged: (_) => notifier.toggleScraping(),
          ),
          const Divider(),
          ListTile(
            title: const Text('スクレイピング間隔'),
            subtitle: Text('${settings.scrapingIntervalSeconds} 秒'),
            trailing: DropdownButton<int>(
              value: settings.scrapingIntervalSeconds,
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
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '有効なSNS',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          for (final service in SnsService.values)
            SwitchListTile(
              title: Text(service.label),
              subtitle: Text(service.domain),
              value: settings.enabledServices.contains(service),
              onChanged: (_) => notifier.toggleService(service),
            ),
        ],
      ),
    );
  }
}
