import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/settings_provider.dart';
import '../../utils/app_snackbar.dart';

/// 一般設定（スリープ防止 / 画像の保存先 / 各種リセット）
class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('一般')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.bedtime_off_outlined),
            title: const Text('画面スリープ防止'),
            subtitle: Text(
              settings.keepScreenOn ? 'ON — バッテリー消費に注意' : 'OFF',
              style: TextStyle(
                color: settings.keepScreenOn ? Colors.orange : null,
              ),
            ),
            value: settings.keepScreenOn,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              notifier.setKeepScreenOn(value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
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
                    final path =
                        '${dir.parent.parent.parent.parent.path}/${settings.imageSaveFolder}';
                    final folder = Directory(path);
                    if (await folder.exists()) {
                      OpenFilex.open(path);
                    } else {
                      if (context.mounted) {
                        showAppSnackBar(
                            context, 'フォルダがまだ存在しません（画像保存時に作成されます）',
                            type: SnackType.info);
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
          if (Platform.isAndroid)
            ListTile(
              leading: const Icon(Icons.picture_in_picture_alt),
              title: const Text('オーバーレイの位置・サイズをリセット'),
              subtitle: const Text('操作不能になった場合に使用'),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('overlay_wIndex');
                await prefs.remove('overlay_hIndex');
                if (context.mounted) {
                  showAppSnackBar(context, 'オーバーレイの設定をリセットしました（次回起動時に反映）',
                      type: SnackType.success);
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('設定をデフォルトに戻す'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('設定をリセット'),
                  content: const Text('すべての設定を初期値に戻します。\nアカウント情報は影響しません。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('キャンセル'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('リセット'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                notifier.resetToDefaults();
                if (context.mounted) {
                  showAppSnackBar(context, '設定をデフォルトに戻しました',
                      type: SnackType.success);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
