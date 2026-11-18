import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/settings_provider.dart';
import '../../services/debug_log_service.dart';
import '../../services/notification_cache_service.dart';
import '../../services/scan_log_service.dart';
import '../../services/timeline_cache_service.dart';
import '../../services/x_features_service.dart';
import '../../services/x_query_id_service.dart';
import '../../utils/app_snackbar.dart';
import '../activity_log_screen.dart';
import '../features_screen.dart';
import '../query_id_screen.dart';
import 'settings_common.dart';

/// デバッグ設定。設定トップのバージョンを5回続けてタップすると
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

  Future<void> _downloadScanLog() async {
    final path = ScanLogService.instance.logFilePath;
    if (path == null || !await File(path).exists()) {
      if (mounted) {
        showAppSnackBar(context, '調査ログはまだありません', type: SnackType.info);
      }
      return;
    }
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final tmpDir = await getTemporaryDirectory();
    final tmpPath = '${tmpDir.path}/omniverse_scan_$ts.log';
    await File(path).copy(tmpPath);
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(tmpPath)],
      text: 'OmniVerse つながり調査ログ ($ts)',
      sharePositionOrigin:
          box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }

  Future<void> _clearScanLog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('調査ログをクリア'),
        content: Text(
            '${ScanLogService.instance.logSizeLabel} の調査ログを削除します。'),
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
      await ScanLogService.instance.clear();
      if (mounted) {
        setState(() {});
        showAppSnackBar(context, '調査ログをクリアしました', type: SnackType.success);
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

  /// ログ 1 本ぶんの行。大きさを添え、送り出しと消去を右に並べる
  Widget _logTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onShare,
    required VoidCallback onClear,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '書き出す',
            onPressed: onShare,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '消す',
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  Widget _link(IconData icon, String title, WidgetBuilder builder) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: builder)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return settingsScaffold(
      title: 'デバッグ',
      body: ListView(
        children: [
          const SettingsSectionHeader(title: 'X の通信'),
          _link(Icons.key_outlined, 'queryId 管理', (_) => const QueryIdScreen()),
          _link(Icons.tune, 'features 管理', (_) => const FeaturesScreen()),
          _link(Icons.receipt_long_outlined, 'アクションログ',
              (_) => const ActivityLogScreen()),
          SwitchListTile(
            secondary: const Icon(Icons.sync),
            title: const Text('タイムライン取得'),
            subtitle: Text(settings.isFetchingActive ? '実行中' : '停止中'),
            value: settings.isFetchingActive,
            onChanged: (_) => notifier.toggleFetching(),
          ),

          const SettingsSectionGap(),
          const SettingsSectionHeader(
              title: 'ログ', subtitle: '不具合を調べるときに書き出して送る'),
          SwitchListTile(
            secondary: const Icon(Icons.fiber_manual_record_outlined),
            title: const Text('通信ログを記録'),
            subtitle: Text(
              settings.debugLogEnabled
                  ? '記録中。容量と動作の重さに注意'
                  : '不具合を再現する前にオンにする',
              style: settings.debugLogEnabled
                  ? TextStyle(fontSize: 12, color: scheme.error)
                  : null,
            ),
            value: settings.debugLogEnabled,
            onChanged: (value) => notifier.setDebugLogEnabled(value),
          ),
          _logTile(
            icon: Icons.storage_outlined,
            title: '通信ログ',
            subtitle: DebugLogService.instance.logSizeLabel,
            onShare: _downloadLog,
            onClear: _clearLog,
          ),
          // つながり調査は数時間かかり、通信ログだと序盤が消えてしまうので
          // 別ファイルに分けている。こちらは常に記録している
          _logTile(
            icon: Icons.travel_explore_outlined,
            title: 'つながり調査のログ',
            subtitle: '${ScanLogService.instance.logSizeLabel}・常に記録',
            onShare: _downloadScanLog,
            onClear: _clearScanLog,
          ),

          const SettingsSectionGap(),
          const SettingsSectionHeader(title: '画面に出す'),
          SwitchListTile(
            secondary: const Icon(Icons.speed),
            title: const Text('パフォーマンス'),
            subtitle: const Text('メモリ・FPS・投稿数を重ねて出す'),
            value: settings.showPerfOverlay,
            onChanged: (value) => notifier.setShowPerfOverlay(value),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.water_drop_outlined),
            title: const Text('ドリップの状態'),
            subtitle: const Text('オーバーレイに出す'),
            value: settings.showDripStatus,
            onChanged: (value) => notifier.setShowDripStatus(value),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.public),
            title: const Text('ブラウザで投稿'),
            subtitle: const Text('投稿画面に WebView で送るボタンを出す'),
            value: settings.debugPostEnabled,
            onChanged: (value) => notifier.setDebugPostEnabled(value),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('画像キャッシュ上限'),
            subtitle: const Text('メモリに置いておく画像の枚数'),
            trailing: DropdownButton<int>(
              value: settings.imageCacheSize,
              underline: const SizedBox.shrink(),
              items: [
                for (final entry in imageCacheSizeOptions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value != null) notifier.setImageCacheSize(value);
              },
            ),
          ),

          // テスト版の経路があるのは自前配布の Android だけ。
          // iOS は App Store の公開版しか入れられない
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            const SettingsSectionGap(),
            const SettingsSectionHeader(title: '更新'),
            SwitchListTile(
              secondary: const Icon(Icons.science_outlined),
              title: const Text('テスト版も受け取る'),
              subtitle: const Text('全員に配る前の版も更新として案内する'),
              value: settings.betaUpdatesEnabled,
              onChanged: (value) => notifier.setBetaUpdatesEnabled(value),
            ),
          ],

          const SettingsSectionGap(),
          const SettingsSectionHeader(title: '片付け'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('キャッシュをクリア'),
            subtitle: const Text('タイムライン・通知・画像・queryId を消す。アカウントは残る'),
            onTap: _clearCache,
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('デバッグを隠す'),
            subtitle: const Text('設定トップのバージョンを 5 回たたくとまた出る'),
            onTap: () {
              ref.read(debugUnlockedProvider.notifier).state = false;
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
