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
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          // Fetching section
          const _SectionHeader(title: 'タイムライン取得'),
          SwitchListTile(
            title: const Text('タイムライン取得'),
            subtitle: Text(settings.isFetchingActive ? '実行中' : '停止中'),
            value: settings.isFetchingActive,
            onChanged: (_) => notifier.toggleFetching(),
          ),
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

          const Divider(),

          // Appearance section
          const _SectionHeader(title: '外観'),
          ListTile(
            title: const Text('テーマ'),
            subtitle: Text(_themeModeLabel(settings.themeMode)),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('システム設定に従う'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text('ライト'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text('ダーク'),
                ),
              ],
              onChanged: (value) {
                if (value != null) notifier.setThemeMode(value);
              },
            ),
          ),
          ListTile(
            title: const Text('フォントサイズ'),
            subtitle: Text('${(settings.fontScale * 100).round()}%'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('A', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: settings.fontScale,
                    min: 0.8,
                    max: 1.5,
                    divisions: 7,
                    label: '${(settings.fontScale * 100).round()}%',
                    onChanged: (value) => notifier.setFontScale(value),
                  ),
                ),
                const Text('A', style: TextStyle(fontSize: 20)),
              ],
            ),
          ),

          const Divider(),

          // About section
          const _SectionHeader(title: 'アプリ情報'),
          const ListTile(
            title: Text('バージョン'),
            trailing: Text('1.0.0'),
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'システム設定に従う',
      ThemeMode.light => 'ライト',
      ThemeMode.dark => 'ダーク',
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
