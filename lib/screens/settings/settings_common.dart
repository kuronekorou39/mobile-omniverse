import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../providers/settings_provider.dart';

/// アプリのバージョン。設定トップの要約とアプリ情報画面で共用する。
final packageVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// タイムラインの取得間隔（秒 → 表示ラベル）。
/// 設定トップの要約表示と詳細画面のドロップダウンで共用する。
const fetchIntervalOptions = <int, String>{
  15: '15秒',
  30: '30秒',
  60: '60秒',
  120: '2分',
  300: '5分',
};

/// ドリップ間隔（ミリ秒 → 表示ラベル）
const dripIntervalOptions = <int, String>{
  500: '0.5秒',
  1000: '1秒',
  1500: '1.5秒',
  2000: '2秒',
  3000: '3秒',
  5000: '5秒',
};

/// 画像メモリキャッシュ上限（枚数 → 表示ラベル）
const imageCacheSizeOptions = <int, String>{
  20: '20枚',
  30: '30枚',
  50: '50枚',
  80: '80枚',
  100: '100枚',
};

String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'システム',
      ThemeMode.light => 'ライト',
      ThemeMode.dark => 'ダーク',
    };

String fontFamilyLabel(String fontFamily) =>
    fontFamily.isEmpty ? 'デフォルト' : fontFamily;

String postCardStyleLabel(PostCardStyle style) => switch (style) {
      PostCardStyle.card => 'カード',
      PostCardStyle.separator => 'セパレート',
    };

String sensitiveModeLabel(SensitiveMode mode) => switch (mode) {
      SensitiveMode.show => '全表示',
      SensitiveMode.hide => '隠す',
      SensitiveMode.hideAll => '全隠し',
    };

String fabPositionLabel(FabPosition position) =>
    position == FabPosition.left ? '左' : '右';

/// 設定トップの遷移行。
/// 現在値を subtitle に出すことで、画面に入らなくても設定状態を一覧できる。
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.title,
    required this.builder,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final WidgetBuilder builder;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: builder)),
    );
  }
}

/// 設定画面の共通枠。
///
/// 戻るボタンと項目のインデントをここで一括して決める。
/// 各画面が個別に padding を書くと、サブ画面で付け忘れて揃わなくなるため、
/// 画面側は title と body だけを渡す。
Widget settingsScaffold({
  required String title,
  required Widget body,
  List<Widget>? actions,
}) {
  return Scaffold(
    appBar: AppBar(
      // 戻るボタンのアイコン左端を、項目のアイコン左端と揃える。
      // IconButton は 48px 幅の中で 24px アイコンを中央に置くので、
      // 左に (settingsIndent - 12) の余白を入れると左端が一致する。
      leadingWidth: 48 + (settingsIndent - 12),
      leading: const Padding(
        padding: EdgeInsets.only(left: settingsIndent - 12),
        child: BackButton(),
      ),
      titleSpacing: 4,
      title: Text(title),
      actions: actions,
      // ヘッダーと中身の境目を出す。インデントを揃えたぶん、
      // ここで区切らないと続きものに見えてしまう。
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1),
      ),
    ),
    // Builder を挟んで Theme を引く（settingsScaffold は context を取らない）
    body: Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return ListTileTheme(
          data: ListTileThemeData(
            contentPadding: settingsItemPadding,
            // 説明文は補助情報なので落とす。主役は項目名
            subtitleTextStyle: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          child: body,
        );
      },
    ),
  );
}

/// 設定画面の左インデント。戻るボタンも項目も見出しもこれに合わせる
const settingsIndent = 24.0;

/// 設定項目の左右余白
const settingsItemPadding = EdgeInsets.only(left: settingsIndent, right: 20);

/// 設定セクションの見出し
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(settingsIndent, 20, 20, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: subtitle != null ? 30 : 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
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
          ),
        ],
      ),
    );
  }
}

/// セクション間の区切り
class SettingsSectionGap extends StatelessWidget {
  const SettingsSectionGap({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12),
      child: Divider(height: 1),
    );
  }
}
