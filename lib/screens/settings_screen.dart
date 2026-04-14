import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/account.dart';
import '../models/sns_service.dart';
import '../providers/settings_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../services/account_storage_service.dart';
import '../services/app_update_service.dart';
import '../services/debug_log_service.dart';
import '../services/notification_cache_service.dart';
import '../services/timeline_cache_service.dart';
import '../services/x_bearer_token_service.dart';
import '../services/x_features_service.dart';
import '../services/x_query_id_service.dart';
import '../widgets/update_dialog.dart';
import 'activity_log_screen.dart';
import 'features_screen.dart';
import 'query_id_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '...';
  int _debugTapCount = 0;
  bool _debugUnlocked = false;

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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
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
          ListTile(
            title: const Text('フォント'),
            subtitle: Text(settings.fontFamily.isEmpty
                ? 'デフォルト'
                : settings.fontFamily),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openFontPicker(context, settings, notifier),
          ),
          ListTile(
            title: Text('フォントサイズ ${(settings.fontScale / 0.8 * 100).round()}%'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('A', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: _FontScaleSlider(
                    value: settings.fontScale,
                    onChanged: (value) => notifier.setFontScale(value),
                  ),
                ),
                const Text('A', style: TextStyle(fontSize: 20)),
              ],
            ),
          ),

          const Divider(),

          // ── レイアウト ──
          const _SectionHeader(title: 'レイアウト'),
          ListTile(
            title: const Text('ボタン位置'),
            trailing: SegmentedButton<FabPosition>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: FabPosition.left, label: Text('左')),
                ButtonSegment(value: FabPosition.right, label: Text('右')),
              ],
              selected: {settings.fabPosition},
              onSelectionChanged: (value) =>
                  notifier.setFabPosition(value.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          ListTile(
            title: const Text('投稿スタイル'),
            trailing: SegmentedButton<PostCardStyle>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: PostCardStyle.card, label: Text('カード')),
                ButtonSegment(value: PostCardStyle.separator, label: Text('セパレート')),
              ],
              selected: {settings.postCardStyle},
              onSelectionChanged: (value) =>
                  notifier.setPostCardStyle(value.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

          const Divider(),

          // ── タイムライン ──
          const _SectionHeader(title: 'タイムライン'),
          ListTile(
            title: const Text('匿名モード'),
            trailing: SegmentedButton<bool>(
              showSelectedIcon: false,
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
          SwitchListTile(
            title: const Text('ヘッダーに匿名切替ボタンを表示'),
            value: settings.appBarButtons.contains('userInfo'),
            onChanged: (_) => notifier.toggleAppBarButton('userInfo'),
            dense: true,
          ),

          const Divider(),

          // ── メディア ──
          const _SectionHeader(title: 'メディア'),
          ListTile(
            title: const Text('プレビューサイズ'),
            trailing: SegmentedButton<ImagePreviewSize>(
              showSelectedIcon: false,
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
            trailing: SegmentedButton<SensitiveMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SensitiveMode.show, label: Text('全表示')),
                ButtonSegment(value: SensitiveMode.hide, label: Text('隠す')),
                ButtonSegment(value: SensitiveMode.hideAll, label: Text('全隠し')),
              ],
              selected: {settings.sensitiveMode},
              onSelectionChanged: (value) =>
                  notifier.setSensitiveMode(value.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('ヘッダーにセンシティブ切替ボタンを表示'),
            value: settings.appBarButtons.contains('sensitive'),
            onChanged: (_) => notifier.toggleAppBarButton('sensitive'),
            dense: true,
          ),
          ListTile(
            title: const Text('画像の保存先'),
            subtitle: Text(settings.imageSaveFolder),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 20),
                  tooltip: 'フォルダを開く',
                  onPressed: () async {
                    final dir = await getExternalStorageDirectory();
                    if (dir == null) return;
                    final path = '${dir.parent.parent.parent.parent.path}/${settings.imageSaveFolder}';
                    final folder = Directory(path);
                    if (await folder.exists()) {
                      OpenFilex.open(path);
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('フォルダがまだ存在しません（画像保存時に作成されます）')),
                        );
                      }
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: '変更',
                  onPressed: () async {
                    final selected = await FilePicker.getDirectoryPath();
                    if (selected == null) return;
                    // ストレージルートからの相対パスに変換
                    final dir = await getExternalStorageDirectory();
                    if (dir == null) return;
                    final root = dir.parent.parent.parent.parent.path;
                    final relative = selected.startsWith(root)
                        ? selected.substring(root.length + 1)
                        : selected;
                    notifier.setImageSaveFolder(relative);
                  },
                ),
              ],
            ),
          ),

          const Divider(),

          // ── フェッチ ──
          const _SectionHeader(title: 'フェッチ', subtitle: 'SNSから投稿を取得する間隔'),
          ListTile(
            title: const Text('取得間隔'),
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
            title: const Text('ドリップ速度'),
            subtitle: const Text('取得した投稿をタイムラインに流す間隔'),
            trailing: DropdownButton<int>(
              value: settings.dripIntervalMs,
              items: const [
                DropdownMenuItem(value: 500, child: Text('0.5秒')),
                DropdownMenuItem(value: 1000, child: Text('1秒')),
                DropdownMenuItem(value: 1500, child: Text('1.5秒')),
                DropdownMenuItem(value: 2000, child: Text('2秒')),
                DropdownMenuItem(value: 3000, child: Text('3秒')),
                DropdownMenuItem(value: 5000, child: Text('5秒')),
              ],
              onChanged: (value) {
                if (value != null) notifier.setDripIntervalMs(value);
              },
            ),
          ),
          SwitchListTile(
            title: const Text('ヘッダーにタイマーを表示'),
            value: settings.showFetchTimer,
            onChanged: (value) => notifier.setShowFetchTimer(value ?? true),
            dense: true,
          ),

          const Divider(),

          // ── アプリ情報 ──
          const _SectionHeader(title: 'アプリ情報'),
          ListTile(
            title: const Text('バージョン'),
            trailing: Text(_version),
            onTap: () {
              if (_debugUnlocked) return;
              _debugTapCount++;
              final remaining = 5 - _debugTapCount;
              if (remaining > 0 && remaining <= 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('あと$remaining回でデバッグモード'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
              if (_debugTapCount >= 5) {
                setState(() => _debugUnlocked = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('デバッグモードが有効になりました')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('アップデート確認'),
            onTap: _checkForUpdate,
          ),
          if (_debugUnlocked) ...[
          const Divider(),

          // ── デバッグ ──
          ExpansionTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('デバッグ'),
            children: [
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
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('queryId 管理'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const QueryIdScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('features 管理'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FeaturesScreen()),
                  );
                },
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('タイムライン取得'),
                subtitle: Text(settings.isFetchingActive ? '実行中' : '停止中'),
                value: settings.isFetchingActive,
                onChanged: (_) => notifier.toggleFetching(),
              ),
              SwitchListTile(
                title: const Text('ブラウザ投稿（デバッグ）'),
                subtitle: const Text('投稿画面にWebView投稿ボタンを表示'),
                value: settings.debugPostEnabled,
                onChanged: (value) => notifier.setDebugPostEnabled(value),
              ),
              SwitchListTile(
                title: const Text('ドリップ状態アイコン'),
                subtitle: const Text('オーバーレイにドリップ状態を表示'),
                value: settings.showDripStatus,
                onChanged: (value) => notifier.setShowDripStatus(value),
              ),
              SwitchListTile(
                title: const Text('パフォーマンスオーバーレイ'),
                subtitle: const Text('メモリ・FPS・投稿数を画面上に表示'),
                value: settings.showPerfOverlay,
                onChanged: (value) => notifier.setShowPerfOverlay(value),
              ),
              ListTile(
                title: const Text('画像キャッシュ上限'),
                subtitle: Text('メモリ上のデコード済み画像の保持枚数（現在: ${settings.imageCacheSize}枚）'),
                trailing: DropdownButton<int>(
                  value: settings.imageCacheSize,
                  items: const [
                    DropdownMenuItem(value: 20, child: Text('20枚')),
                    DropdownMenuItem(value: 30, child: Text('30枚')),
                    DropdownMenuItem(value: 50, child: Text('50枚')),
                    DropdownMenuItem(value: 80, child: Text('80枚')),
                    DropdownMenuItem(value: 100, child: Text('100枚')),
                  ],
                  onChanged: (value) {
                    if (value != null) notifier.setImageCacheSize(value);
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('通信ログを記録'),
                subtitle: Text(
                  settings.debugLogEnabled
                      ? 'ON — ストレージ消費・パフォーマンス低下の可能性あり'
                      : 'OFF — 問題発生時にONにしてください',
                  style: TextStyle(
                    fontSize: 12,
                    color: settings.debugLogEnabled ? Colors.orange : Colors.grey,
                  ),
                ),
                value: settings.debugLogEnabled,
                onChanged: (value) => notifier.setDebugLogEnabled(value),
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
              const Divider(),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('キャッシュをクリア'),
                subtitle: const Text('タイムライン・通知・画像・queryIdを削除（アカウント情報は残る）'),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('キャッシュをクリア'),
                      content: const Text(
                        'タイムライン、通知、画像キャッシュ、queryId、Bearer Tokenを削除します。\n\nアカウント情報は残ります。クリア後にアプリが再取得を開始します。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('キャンセル'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('クリア'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;

                  // タイムラインキャッシュ
                  await TimelineCacheService.instance.clearCache();
                  // 通知キャッシュ
                  NotificationCacheService.instance.clearAll();
                  // 画像キャッシュ（ディスク + メモリ）
                  await DefaultCacheManager().emptyCache();
                  PaintingBinding.instance.imageCache.clear();
                  PaintingBinding.instance.imageCache.clearLiveImages();
                  // queryId キャッシュ
                  await XQueryIdService.instance.clearCache();
                  // features キャッシュ
                  await XFeaturesService.instance.clearCache();
                  // Bearer Token キャッシュ
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('x_bearer_token');
                  // デバッグログ
                  await DebugLogService.instance.clear();

                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('キャッシュをクリアしました。アプリを再起動してください。')),
                    );
                  }
                },
              ),
            ],
          ),
          ], // _debugUnlocked
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

/// フォントサイズスライダー: ドラッグ中はローカルstateのみ更新、
/// 指を離したときにグローバルstate（MediaQuery）を更新。
/// アプリ全体の再構築が毎フレーム走るのを防ぐ。
class _FontScaleSlider extends StatefulWidget {
  const _FontScaleSlider({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_FontScaleSlider> createState() => _FontScaleSliderState();
}

class _FontScaleSliderState extends State<_FontScaleSlider> {
  late double _localValue;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant _FontScaleSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) _localValue = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _localValue.clamp(0.6, 1.5),
      min: 0.6,
      max: 1.5,
      divisions: 9,
      onChanged: (value) {
        setState(() {
          _dragging = true;
          _localValue = value;
        });
      },
      onChangeEnd: (value) {
        _dragging = false;
        widget.onChanged(value);
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
        ],
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
