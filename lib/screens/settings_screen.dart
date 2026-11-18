import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../services/app_update_service.dart';
import '../utils/app_snackbar.dart';
import '../widgets/update_dialog.dart';
import 'settings/appearance_settings_screen.dart';
import 'settings/button_layout_settings_screen.dart';
import 'settings/debug_settings_screen.dart';
import 'settings/general_settings_screen.dart';
import 'settings/post_display_settings_screen.dart';
import 'settings/settings_common.dart';
import 'settings/timeline_settings_screen.dart';

/// 設定トップ。操作系は置かず、各詳細画面への入口だけを大きなタイルで並べる。
/// バージョンと更新の確認は、タイルの下に小さく添える。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debugUnlocked = ref.watch(debugUnlockedProvider);

    return settingsScaffold(
      title: '設定',
      body: Column(
        children: [
          Expanded(
            child: SettingsNavGrid(
              children: [
                SettingsNavTile(
                  icon: Icons.palette_outlined,
                  title: '外観',
                  builder: (_) => const AppearanceSettingsScreen(),
                ),
                SettingsNavTile(
                  icon: Icons.article_outlined,
                  title: '投稿の表示',
                  builder: (_) => const PostDisplaySettingsScreen(),
                ),
                SettingsNavTile(
                  icon: Icons.timer_outlined,
                  title: 'タイムライン',
                  builder: (_) => const TimelineSettingsScreen(),
                ),
                SettingsNavTile(
                  icon: Icons.swap_horiz,
                  title: 'ボタン配置',
                  builder: (_) => const ButtonLayoutSettingsScreen(),
                ),
                SettingsNavTile(
                  icon: Icons.settings_outlined,
                  title: '一般',
                  builder: (_) => const GeneralSettingsScreen(),
                ),
                if (debugUnlocked)
                  SettingsNavTile(
                    icon: Icons.bug_report_outlined,
                    title: 'デバッグ',
                    builder: (_) => const DebugSettingsScreen(),
                  ),
              ],
            ),
          ),
          const SafeArea(top: false, child: _VersionFooter()),
        ],
      ),
    );
  }
}

/// 設定トップの下端に出すバージョンと「更新を確認」。
/// バージョンの数字を続けて 5 回たたくとデバッグのタイルが出る（押した見た目は出さない）
class _VersionFooter extends ConsumerStatefulWidget {
  const _VersionFooter();

  @override
  ConsumerState<_VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends ConsumerState<_VersionFooter> {
  /// デバッグを出すのに要る連続タップの回数
  static const _unlockTaps = 5;

  /// これより間が空いたら数え直す
  static const _tapWindow = Duration(milliseconds: 600);

  int _taps = 0;
  Timer? _tapReset;
  bool _checking = false;

  @override
  void dispose() {
    _tapReset?.cancel();
    super.dispose();
  }

  void _onVersionTap() {
    if (ref.read(debugUnlockedProvider)) return;
    _tapReset?.cancel();
    _tapReset = Timer(_tapWindow, () => _taps = 0);
    if (++_taps >= _unlockTaps) {
      _taps = 0;
      ref.read(debugUnlockedProvider.notifier).state = true;
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checking = true);
    final info = await AppUpdateService.instance.checkForUpdate();
    if (!mounted) return;
    setState(() => _checking = false);
    if (info != null) {
      showUpdateDialog(context, info);
    } else {
      showAppSnackBar(context, '最新バージョンです');
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(packageVersionProvider).asData?.value ?? '...';
    final faint = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('OmniVerse ', style: TextStyle(fontSize: 12, color: faint)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onVersionTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('v$version',
                  style: TextStyle(fontSize: 12, color: faint)),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _checking ? null : _checkForUpdate,
            child: Text(_checking ? '確認中…' : '更新を確認'),
          ),
        ],
      ),
    );
  }
}
