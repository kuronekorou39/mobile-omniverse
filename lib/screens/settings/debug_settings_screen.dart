import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/settings_provider.dart';
import '../../services/debug_log_service.dart';
import '../../services/notification_cache_service.dart';
import '../../services/timeline_cache_service.dart';
import '../../services/x_features_service.dart';
import '../../services/x_query_id_service.dart';
import '../../utils/app_snackbar.dart';
import '../activity_log_screen.dart';
import '../features_screen.dart';
import '../query_id_screen.dart';
import 'settings_common.dart';

/// デバッグ設定。アプリ情報画面でバージョンを5回タップすると
/// 設定トップに入口が現れる。
class DebugSettingsScreen extends ConsumerStatefulWidget {
  const DebugSettingsScreen({super.key});

  @override
  ConsumerState<DebugSettingsScreen> createState() =>
      _DebugSettingsScreenState();
}

class _DebugSettingsScreenState extends ConsumerState<DebugSettingsScreen> {
  Future<void> _downloadLog() async {
    final path = DebugLogService.instance.logFilePath;
    if (path == null) return;
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final tmpDir = await getTemporaryDirectory();
    final tmpPath = '${tmpDir.path}/omniverse_debug_$ts.log';
    await File(path).copy(tmpPath);
    if (!mounted) return;
    // iPad では sharePositionOrigin を渡さないと popover 未指定で落ちる
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(tmpPath)],
      text: 'OmniVerse デバッグログ ($ts)',
      sharePositionOrigin:
          box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }

  Future<void> _clearLog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログをクリア'),
        content: Text('${DebugLogService.instance.logSizeLabel} のログを削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('クリア'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DebugLogService.instance.clear();
      if (mounted) {
        setState(() {});
        showAppSnackBar(context, 'ログをクリアしました', type: SnackType.success);
      }
    }
  }

  Future<void> _clearCache() async {
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
      showAppSnackBar(context, 'キャッシュをクリアしました。アプリを再起動してください。',
          type: SnackType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return settingsScaffold(
      title: 'デバッグ',
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('アクションログ'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('queryId 管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const QueryIdScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('features 管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FeaturesScreen()),
            ),
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
              items: [
                for (final entry in imageCacheSizeOptions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
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
            onTap: _downloadLog,
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep),
            title: const Text('ログをクリア'),
            onTap: _clearLog,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('キャッシュをクリア'),
            subtitle: const Text('タイムライン・通知・画像・queryIdを削除（アカウント情報は残る）'),
            onTap: _clearCache,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('デバッグメニューを隠す'),
            subtitle: const Text('設定からこの項目を消す（バージョン5回タップで再表示）'),
            onTap: () {
              ref.read(debugUnlockedProvider.notifier).state = false;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
