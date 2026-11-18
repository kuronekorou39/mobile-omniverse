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
///
/// 確認の結果はこの行の中に出す。下からの知らせだと、この行に被って読めない
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

  /// 「最新です」を出しておく長さ
  static const _resultShown = Duration(seconds: 3);

  int _taps = 0;
  Timer? _tapReset;
  Timer? _resultReset;
  bool _checking = false;
  bool _upToDate = false;

  @override
  void dispose() {
    _tapReset?.cancel();
    _resultReset?.cancel();
    super.dispose();
  }

  void _onVersionTap() {
    if (ref.read(debugUnlockedProvider)) return;
    _tapReset?.cancel();
    _tapReset = Timer(_tapWindow, () => _taps = 0);
    if (++_taps >= _unlockTaps) {
      _taps = 0;
      ref.read(debugUnlockedProvider.notifier).state = true;
      showAppSnackBar(context, '設定にデバッグを出しました',
          type: SnackType.success);
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checking = true);
    final info = await AppUpdateService.instance.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _upToDate = info == null;
    });
    if (info != null) {
      showUpdateDialog(context, info);
      return;
    }
    _resultReset?.cancel();
    _resultReset = Timer(_resultShown, () {
      if (mounted) setState(() => _upToDate = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(packageVersionProvider).asData?.value ?? '...';
    final scheme = Theme.of(context).colorScheme;
    final faint = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    // 中央から左右に振り分ける。右側の文言が変わってもバージョンは動かない
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onVersionTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('OmniVerse v$version', style: faint),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _upToDate
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, size: 14, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text('最新です', style: faint),
                        ],
                      ),
                    )
                  : TextButton(
                      style: TextButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      // 確認中も文言は変えない。幅が変わって並びがぶれる
                      onPressed: _checking ? null : _checkForUpdate,
                      child: const Text('更新を確認'),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
