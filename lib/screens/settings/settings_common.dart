import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../providers/settings_provider.dart';

/// アプリのバージョン。設定トップの下端に出す。
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

/// 設定トップの正方形タイル。記号と名前だけを大きく中央に置く。
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.title,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: builder)),
        // 記号と文字はタイルの大きさに合わせて伸ばす。
        // 固定にすると iPad の大きなタイルの中で小さく取り残される
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: side * 0.38, color: scheme.primary),
                SizedBox(height: side * 0.06),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: side * 0.115,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 設定トップのタイルの並び。
///
/// 画面の幅と高さの両方を見て、全部のタイルがスクロール無しで収まり、
/// かつ 1 枚がいちばん大きくなる列数を選ぶ。幅だけで決めると、
/// スマホの横向きのように低い画面で下の段がはみ出す。
class SettingsNavGrid extends StatelessWidget {
  const SettingsNavGrid({super.key, required this.children});

  final List<Widget> children;

  /// タイル 1 枚の辺の上限。タブレットで間延びしない大きさ
  static const _maxTileSide = 300.0;

  /// これより小さくするくらいなら、収めるのをやめてスクロールさせる
  static const _minTileSide = 96.0;

  static const _gap = 16.0;

  /// [columns] 列で並べたときに、はみ出さずに取れるタイルの辺
  double _sideFor(int columns, BoxConstraints area) {
    final rows = (children.length / columns).ceil();
    final byWidth = (area.maxWidth - _gap * (columns + 1)) / columns;
    final byHeight = (area.maxHeight - _gap * (rows + 1)) / rows;
    return byWidth < byHeight ? byWidth : byHeight;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, area) {
        var columns = 1;
        var side = 0.0;
        for (var c = 1; c <= children.length; c++) {
          final candidate = _sideFor(c, area);
          if (candidate > side) {
            columns = c;
            side = candidate;
          }
        }
        side = side.clamp(_minTileSide, _maxTileSide);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(_gap),
          child: Center(
            child: SizedBox(
              width: side * columns + _gap * (columns - 1),
              child: Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [
                  for (final child in children)
                    SizedBox.square(dimension: side, child: child),
                ],
              ),
            ),
          ),
        );
      },
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
            // 形だけ渡すと設定のフォントが外れる。テーマの文字から作る
            subtitleTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
