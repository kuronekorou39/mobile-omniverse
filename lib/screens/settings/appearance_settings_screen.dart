import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/settings_provider.dart';
import '../../utils/app_snackbar.dart';
import 'settings_common.dart';

/// 外観設定（テーマ / フォント / フォントサイズ）
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('外観')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('テーマ'),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              items: [
                for (final mode in ThemeMode.values)
                  DropdownMenuItem(
                    value: mode,
                    child: Text(themeModeLabel(mode)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) notifier.setThemeMode(value);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.font_download_outlined),
            title: const Text('フォント'),
            subtitle: Text(fontFamilyLabel(settings.fontFamily)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openFontPicker(context, settings, notifier),
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title:
                Text('フォントサイズ ${(settings.fontScale / 0.8 * 100).round()}%'),
            subtitle: Row(
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
        ],
      ),
    );
  }
}

/// 利用可能な日本語フォント定義
const _japaneseFonts = <({String name, String label})>[
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

const _prefsCachedFontsKey = 'cached_google_fonts';

/// ダウンロード済みフォントを SharedPreferences で管理
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

void _openFontPicker(
  BuildContext context,
  SettingsState settings,
  SettingsNotifier notifier,
) {
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
      showAppSnackBar(context, 'ダウンロード失敗: $e', type: SnackType.error);
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
                showAppSnackBar(context, 'キャッシュを削除しました。再度タップでダウンロードできます。',
                    type: SnackType.success);
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
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : isSelected
                          ? Icon(Icons.radio_button_checked,
                              color: Theme.of(context).colorScheme.primary)
                          : const Icon(Icons.radio_button_unchecked),
                  onTap: isDownloading ? null : () => _onFontTap(font.name),
                  onLongPress:
                      font.name.isEmpty ? null : () => _onFontLongPress(font.name),
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
