import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/settings_provider.dart';
import '../../services/app_update_service.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/update_dialog.dart';
import 'settings_common.dart';

/// アプリ情報（バージョン / アップデート確認 / プライバシーポリシー）
class AboutSettingsScreen extends ConsumerStatefulWidget {
  const AboutSettingsScreen({super.key});

  @override
  ConsumerState<AboutSettingsScreen> createState() =>
      _AboutSettingsScreenState();
}

class _AboutSettingsScreenState extends ConsumerState<AboutSettingsScreen> {
  int _debugTapCount = 0;

  Future<void> _checkForUpdate() async {
    final info = await AppUpdateService.instance.checkForUpdate();
    if (!mounted) return;
    if (info != null) {
      showUpdateDialog(context, info);
    } else {
      showAppSnackBar(context, '最新バージョンです');
    }
  }

  /// バージョンを5回タップで設定トップにデバッグ行を表示する隠し機能。
  /// 表示先が別画面になるので、解錠できたことをスナックバーで知らせる。
  void _onVersionTap() {
    if (ref.read(debugUnlockedProvider)) return;
    _debugTapCount++;
    if (_debugTapCount >= 5) {
      ref.read(debugUnlockedProvider.notifier).state = true;
      showAppSnackBar(context, '設定にデバッグメニューを表示しました',
          type: SnackType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(packageVersionProvider).asData?.value ?? '...';

    return settingsScaffold(
      title: 'アプリ情報',
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('バージョン'),
            trailing: Text(version),
            onTap: _onVersionTap,
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('アップデート確認'),
            onTap: _checkForUpdate,
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('プライバシーポリシー・免責事項'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => launchUrl(
              Uri.parse('https://rou39.com/omniverse/privacy-policy.html'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }
}
