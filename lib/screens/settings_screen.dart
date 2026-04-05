import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
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
          ListTile(
            title: const Text('匿名モード'),
            trailing: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('通常表示')),
                ButtonSegment(value: true, label: Text('匿名表示')),
              ],
              selected: {settings.hideUserInfo},
              onSelectionChanged: (value) =>
                  notifier.setHideUserInfo(value.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

          const Divider(),

          // ── メディア ──
          const _SectionHeader(title: 'メディア'),
          ListTile(
            title: const Text('プレビューサイズ'),
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
          ListTile(
            title: const Text('センシティブ'),
            trailing: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('隠す')),
                ButtonSegment(value: false, label: Text('全て表示')),
              ],
              selected: {!settings.showSensitiveContent},
              onSelectionChanged: (value) =>
                  notifier.setShowSensitiveContent(!value.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

          const Divider(),

          // ── 文章 ──
          const _SectionHeader(title: '文章'),
          ListTile(
            title: const Text('フォント'),
            subtitle: Text(settings.fontFamily.isEmpty
                ? 'デフォルト'
                : settings.fontFamily),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openFontPicker(context, settings, notifier),
          ),
          ListTile(
            title: Text('サイズ ${(settings.fontScale * 100).round()}%'),
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

          // ── ヘッダー ──
          const _SectionHeader(title: 'ヘッダー'),
          CheckboxListTile(
            secondary: const Icon(Icons.timer_outlined, size: 20),
            title: const Text('フェッチタイマー'),
            value: settings.showFetchTimer,
            onChanged: (value) => notifier.setShowFetchTimer(value ?? true),
            dense: true,
          ),
          CheckboxListTile(
            secondary: const Icon(Icons.blur_on, size: 20),
            title: const Text('センシティブ切替'),
            value: settings.appBarButtons.contains('sensitive'),
            onChanged: (_) => notifier.toggleAppBarButton('sensitive'),
            dense: true,
          ),
          CheckboxListTile(
            secondary: const Icon(Icons.face_retouching_off, size: 20),
            title: const Text('匿名モード切替'),
            value: settings.appBarButtons.contains('userInfo'),
            onChanged: (_) => notifier.toggleAppBarButton('userInfo'),
            dense: true,
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
                  final tmpDir = await getTemporaryDirectory();
                  final tmpPath = '${tmpDir.path}/omniverse_debug_$ts.log';
                  await File(path).copy(tmpPath);
                  await Share.shareXFiles(
                    [XFile(tmpPath)],
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

  /// 利用可能な日本語フォント定義
  static const _japaneseFonts = <({String name, String label})>[
    (name: '', label: 'デフォルト'),
    (name: 'Noto Sans JP', label: 'Noto Sans JP（ゴシック）'),
    (name: 'Noto Serif JP', label: 'Noto Serif JP（明朝）'),
    (name: 'M PLUS Rounded 1c', label: 'M PLUS Rounded（丸ゴシック）'),
    (name: 'Zen Maru Gothic', label: 'Zen Maru Gothic（丸ゴシック）'),
    (name: 'Klee One', label: 'Klee One（教科書体）'),
    (name: 'Shippori Mincho', label: 'しっぽり明朝'),
    (name: 'Hachi Maru Pop', label: 'はちまるポップ（手書き）'),
    (name: 'DotGothic16', label: 'DotGothic16（ドット）'),
  ];

  static const _prefsCachedFontsKey = 'cached_google_fonts';

  /// ダウンロード済みフォントをSharedPreferencesで管理
  Future<bool> _isFontCached(String fontName) async {
    if (fontName.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList(_prefsCachedFontsKey) ?? [];
    return cached.contains(fontName);
  }

  Future<void> _markFontCached(String fontName) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList(_prefsCachedFontsKey) ?? [];
    if (!cached.contains(fontName)) {
      cached.add(fontName);
      await prefs.setStringList(_prefsCachedFontsKey, cached);
    }
  }

  Future<void> _clearFontCache(String fontName) async {
    // SharedPreferencesから削除
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList(_prefsCachedFontsKey) ?? [];
    cached.remove(fontName);
    await prefs.setStringList(_prefsCachedFontsKey, cached);
    // ファイルシステム上のキャッシュも削除を試みる
    try {
      final dir = await getApplicationSupportDirectory();
      for (final subDir in ['google_fonts', 'fonts']) {
        final fontDir = Directory('${dir.path}/$subDir');
        if (!await fontDir.exists()) continue;
        final prefix = fontName.replaceAll(' ', '');
        final files = await fontDir.list().toList();
        for (final f in files) {
          if (f.path.contains(prefix)) await f.delete();
        }
      }
    } catch (_) {}
  }

  void _openFontPicker(BuildContext context, SettingsState settings, SettingsNotifier notifier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FontPickerSheet(
        currentFont: settings.fontFamily,
        fonts: _japaneseFonts,
        isFontCached: _isFontCached,
        markFontCached: _markFontCached,
        clearFontCache: _clearFontCache,
        onSelect: (name) {
          notifier.setFontFamily(name);
          Navigator.of(ctx).pop();
        },
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

  String _fontLabel(String family) => switch (family) {
        '' => 'デフォルト',
        'serif' => '明朝体',
        'monospace' => '等幅',
        'sans-serif-condensed' => 'コンデンス',
        'cursive' => '手書き風',
        _ => family,
      };

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

/// フォント選択ボトムシート
class _FontPickerSheet extends StatefulWidget {
  const _FontPickerSheet({
    required this.currentFont,
    required this.fonts,
    required this.isFontCached,
    required this.markFontCached,
    required this.clearFontCache,
    required this.onSelect,
  });

  final String currentFont;
  final List<({String name, String label})> fonts;
  final Future<bool> Function(String) isFontCached;
  final Future<void> Function(String) markFontCached;
  final Future<void> Function(String) clearFontCache;
  final void Function(String) onSelect;

  @override
  State<_FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends State<_FontPickerSheet> {
  final Map<String, bool> _cacheStatus = {};
  String? _downloading;

  @override
  void initState() {
    super.initState();
    _checkAllCache();
  }

  Future<void> _checkAllCache() async {
    for (final font in widget.fonts) {
      final cached = await widget.isFontCached(font.name);
      if (mounted) setState(() => _cacheStatus[font.name] = cached);
    }
  }

  Future<void> _downloadAndSelect(String fontName) async {
    setState(() => _downloading = fontName);
    try {
      await GoogleFonts.pendingFonts([
        GoogleFonts.getFont(fontName),
      ]);
      await widget.markFontCached(fontName);
      if (!mounted) return;
      widget.onSelect(fontName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ダウンロード失敗: $e')),
      );
      setState(() => _downloading = null);
    }
  }

  void _onFontTap(String fontName) {
    // デフォルト
    if (fontName.isEmpty) {
      widget.onSelect('');
      return;
    }

    final isCached = _cacheStatus[fontName] ?? false;

    if (isCached) {
      // キャッシュ済み → 即適用
      widget.onSelect(fontName);
    } else {
      // 未キャッシュ → 確認モーダル
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('フォントのダウンロード'),
          content: Text('「$fontName」をダウンロードしますか？\n（初回のみ、以降はキャッシュから読み込みます）'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _downloadAndSelect(fontName);
              },
              child: const Text('ダウンロード'),
            ),
          ],
        ),
      );
    }
  }

  void _onFontLongPress(String fontName) {
    if (fontName.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fontName),
        content: const Text('キャッシュを削除して再ダウンロードしますか？\nフォントが正しく表示されない場合にお試しください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await widget.clearFontCache(fontName);
              setState(() => _cacheStatus[fontName] = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('キャッシュを削除しました。再度タップでダウンロードできます。')),
                );
              }
            },
            child: const Text('削除して再ダウンロード'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'フォント選択',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.fonts.length,
              itemBuilder: (context, index) {
                final font = widget.fonts[index];
                final isSelected = font.name == widget.currentFont;
                final isCached = _cacheStatus[font.name] ?? (font.name.isEmpty);
                final isDownloading = _downloading == font.name;

                return ListTile(
                  leading: font.name.isEmpty
                      ? const Icon(Icons.text_fields)
                      : isCached
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.cloud_download_outlined),
                  title: Text(font.label),
                  trailing: isDownloading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : isSelected
                          ? Icon(Icons.radio_button_checked,
                              color: Theme.of(context).colorScheme.primary)
                          : const Icon(Icons.radio_button_unchecked),
                  onTap: isDownloading ? null : () => _onFontTap(font.name),
                  onLongPress: font.name.isEmpty ? null : () => _onFontLongPress(font.name),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              '長押しでキャッシュ削除・再ダウンロード',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }
}
