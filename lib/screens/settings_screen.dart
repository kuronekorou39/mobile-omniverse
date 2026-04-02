import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../providers/settings_provider.dart';
import '../services/account_storage_service.dart';
import '../services/app_update_service.dart';
import '../services/debug_log_service.dart';
import '../services/x_query_id_service.dart';
import '../widgets/update_dialog.dart';
import 'activity_log_screen.dart';

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
    final before = Map<String, String>.from(XQueryIdService.instance.currentIds(creds: creds));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('queryId を更新中...')),
    );

    final count = await XQueryIdService.instance.forceRefresh(creds);

    if (!mounted) return;

    final after = XQueryIdService.instance.currentIds(creds: creds);

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
          // ── タイムライン ──
          const _SectionHeader(title: 'タイムライン'),
          ListTile(
            title: const Text('フェッチ間隔'),
            subtitle: Text('${settings.fetchIntervalSeconds} 秒ごとに取得'),
            trailing: DropdownButton<int>(
              value: settings.fetchIntervalSeconds,
              items: const [
                DropdownMenuItem(value: 15, child: Text('15秒')),
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
          SwitchListTile(
            title: const Text('フェッチタイマー表示'),
            subtitle: const Text('AppBar にカウントダウンを表示'),
            value: settings.showFetchTimer,
            onChanged: (value) => notifier.setShowFetchTimer(value),
          ),
          SwitchListTile(
            title: const Text('ユーザー情報を表示'),
            subtitle: const Text('アイコン・名前・ハンドルを表示する'),
            value: !settings.hideUserInfo,
            onChanged: (value) => notifier.setHideUserInfo(!value),
          ),

          const Divider(),

          // ── メディア ──
          const _SectionHeader(title: 'メディア'),
          ListTile(
            title: const Text('プレビューサイズ'),
            subtitle: Text(settings.imagePreviewSize.label),
            trailing: SegmentedButton<ImagePreviewSize>(
              segments: const [
                ButtonSegment(value: ImagePreviewSize.small, label: Text('小')),
                ButtonSegment(value: ImagePreviewSize.medium, label: Text('中')),
                ButtonSegment(value: ImagePreviewSize.large, label: Text('大')),
              ],
              selected: {settings.imagePreviewSize},
              onSelectionChanged: (value) =>
                  notifier.setImagePreviewSize(value.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('センシティブ警告を表示'),
            subtitle: const Text('センシティブなメディアをぼかす'),
            value: !settings.showSensitiveContent,
            onChanged: (value) => notifier.setShowSensitiveContent(!value),
          ),

          const Divider(),

          // ── 文章 ──
          const _SectionHeader(title: '文章'),
          ListTile(
            title: const Text('フォント'),
            subtitle: Text(settings.fontFamily.isEmpty ? 'システムデフォルト' : settings.fontFamily),
            trailing: DropdownButton<String>(
              value: settings.fontFamily,
              items: const [
                DropdownMenuItem(value: '', child: Text('システムデフォルト')),
                DropdownMenuItem(value: 'Noto Sans JP', child: Text('Noto Sans JP')),
                DropdownMenuItem(value: 'Roboto', child: Text('Roboto')),
                DropdownMenuItem(value: 'monospace', child: Text('等幅')),
              ],
              onChanged: (value) {
                if (value != null) notifier.setFontFamily(value);
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

          // ── 外観 ──
          const _SectionHeader(title: '外観'),
          ListTile(
            title: const Text('テーマ'),
            subtitle: Text(_themeModeLabel(settings.themeMode)),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('システム')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('ライト')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('ダーク')),
              ],
              onChanged: (value) {
                if (value != null) notifier.setThemeMode(value);
              },
            ),
          ),

          const Divider(),

          // ── アプリ情報 ──
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
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('アクションログ'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
              );
            },
          ),

          const Divider(),

          // ── デバッグ ──
          ExpansionTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('デバッグ'),
            children: [
              SwitchListTile(
                title: const Text('タイムライン取得'),
                subtitle: Text(settings.isFetchingActive ? '実行中' : '停止中'),
                value: settings.isFetchingActive,
                onChanged: (_) => notifier.toggleFetching(),
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('queryId 更新'),
                subtitle: Text(
                  _hasXAccount
                      ? (XQueryIdService.instance.lastRefreshTime() != null
                          ? '最終更新: ${_formatTime(XQueryIdService.instance.lastRefreshTime()!)}'
                          : '未更新')
                      : 'X アカウントが必要です',
                ),
                onTap: _hasXAccount ? _refreshQueryIds : null,
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('queryId キャッシュ消去'),
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
              const Divider(),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('通信ログ'),
                subtitle: Text(DebugLogService.instance.logSizeLabel),
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('ログをダウンロード'),
                onTap: () async {
                  final path = DebugLogService.instance.logFilePath;
                  if (path == null) return;
                  final now = DateTime.now();
                  final ts = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
                  await Share.shareXFiles(
                    [XFile(path, name: 'omniverse_debug_$ts.log')],
                    text: 'OmniVerse デバッグログ ($ts)',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep),
                title: const Text('ログをクリア'),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('ログをクリア'),
                      content: Text('${DebugLogService.instance.logSizeLabel} のログを削除します。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('キャンセル'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('クリア'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await DebugLogService.instance.clear();
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ログをクリアしました')),
                      );
                    }
                  }
                },
              ),
            ],
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
