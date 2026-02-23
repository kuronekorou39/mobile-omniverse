import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../providers/settings_provider.dart';
import '../services/account_storage_service.dart';
import '../services/app_update_service.dart';
import '../services/x_query_id_service.dart';
import '../widgets/update_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '...';

  bool get _hasXAccount => AccountStorageService.instance.accounts
      .any((a) => a.service == SnsService.x && a.isEnabled);

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = info.version);
    }
  }

  Future<void> _checkForUpdate() async {
    final info = await AppUpdateService.instance.checkForUpdate();
    if (!mounted) return;
    if (info != null) {
      showUpdateDialog(context, info);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最新バージョンです')),
      );
    }
  }

  Future<void> _refreshQueryIds() async {
    // X アカウントの credentials を取得
    XCredentials? creds;
    for (final account in AccountStorageService.instance.accounts) {
      if (account.service == SnsService.x && account.isEnabled) {
        creds = account.xCredentials;
        break;
      }
    }

    // リフレッシュ前の値を記録
    final before = Map<String, String>.from(XQueryIdService.instance.currentIds);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('queryId を更新中...')),
    );

    final count = await XQueryIdService.instance.forceRefresh(creds);

    if (!mounted) return;

    final after = XQueryIdService.instance.currentIds;

    // 前後の差分を作成
    final lines = <String>[];
    for (final op in after.keys) {
      final b = before[op] ?? '(なし)';
      final a = after[op]!;
      final changed = b != a ? ' *' : '';
      lines.add('$op:\n  $b → $a$changed');
    }

    // ダイアログで表示
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('queryId 更新結果 ($count 件変更)'),
        content: SingleChildScrollView(
          child: Text(
            lines.join('\n\n'),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

          // Engagement section
          const _SectionHeader(title: 'エンゲージメント'),
          SwitchListTile(
            title: const Text('アカウント選択モーダル'),
            subtitle: const Text('いいね/RT 時にアカウントを選択する'),
            value: settings.showAccountPickerOnEngagement,
            onChanged: (value) => notifier.setShowAccountPicker(value),
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

          // RT filter per account
          const _SectionHeader(title: 'RT/リポスト フィルタ'),
          ...AccountStorageService.instance.accounts.map((account) {
            final isHidden = settings.hideRetweetsAccountIds.contains(account.id);
            return SwitchListTile(
              title: Text(account.displayName),
              subtitle: Text(
                '${account.handle} (${account.service.name.toUpperCase()})',
              ),
              secondary: Icon(
                account.service == SnsService.x ? Icons.close : Icons.cloud,
                size: 20,
              ),
              value: isHidden,
              onChanged: (_) => notifier.toggleHideRetweets(account.id),
            );
          }),
          if (AccountStorageService.instance.accounts.isEmpty)
            const ListTile(
              title: Text('アカウントがありません'),
              subtitle: Text('アカウントを追加すると、ここで RT 非表示を設定できます'),
            ),

          const Divider(),

          // About section
          const _SectionHeader(title: 'アプリ情報'),
          ListTile(
            title: const Text('バージョン'),
            trailing: Text(_version),
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('アップデート確認'),
            onTap: _checkForUpdate,
          ),

          const Divider(),

          // Debug section
          const _SectionHeader(title: 'デバッグ'),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('queryId 更新'),
            subtitle: Text(
              _hasXAccount
                  ? (XQueryIdService.instance.lastRefreshTime != null
                      ? '最終更新: ${_formatTime(XQueryIdService.instance.lastRefreshTime!)}'
                      : '未更新')
                  : 'X アカウントが必要です',
            ),
            onTap: _hasXAccount ? _refreshQueryIds : null,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('queryId キャッシュ消去'),
            subtitle: const Text('デフォルト値に戻します'),
            onTap: () async {
              await XQueryIdService.instance.clearCache();
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('queryId キャッシュを消去しました')),
                );
              }
            },
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

  String _formatTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
