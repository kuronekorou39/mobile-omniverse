import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import 'settings_common.dart';

/// 投稿の表示設定。プレビューを上部に固定し、変更結果がその場で見えるようにする。
class PostDisplaySettingsScreen extends ConsumerWidget {
  const PostDisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('投稿の表示')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsSectionHeader(title: 'プレビュー'),
                _PostStylePreview(
                  postCardStyle: settings.postCardStyle,
                  hideUserInfo: settings.hideUserInfo,
                  sensitiveMode: settings.sensitiveMode,
                  imagePreviewSize: settings.imagePreviewSize,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.view_agenda_outlined),
                  title: const Text('投稿スタイル'),
                  trailing: SegmentedButton<PostCardStyle>(
                    showSelectedIcon: false,
                    segments: [
                      for (final style in PostCardStyle.values)
                        ButtonSegment(
                          value: style,
                          label: Text(postCardStyleLabel(style)),
                        ),
                    ],
                    selected: {settings.postCardStyle},
                    onSelectionChanged: (value) =>
                        notifier.setPostCardStyle(value.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_size_select_large_outlined),
                  title: const Text('プレビューサイズ'),
                  trailing: SegmentedButton<ImagePreviewSize>(
                    showSelectedIcon: false,
                    segments: [
                      for (final size in ImagePreviewSize.values)
                        ButtonSegment(value: size, label: Text(size.label)),
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
                  leading: const Icon(Icons.visibility_off_outlined),
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
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('センシティブ'),
                  trailing: SegmentedButton<SensitiveMode>(
                    showSelectedIcon: false,
                    segments: [
                      for (final mode in SensitiveMode.values)
                        ButtonSegment(
                          value: mode,
                          label: Text(sensitiveModeLabel(mode)),
                        ),
                    ],
                    selected: {settings.sensitiveMode},
                    onSelectionChanged: (value) =>
                        notifier.setSensitiveMode(value.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
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

/// 投稿スタイルのプレビュー（カード/セパレート・匿名・センシティブを1つで表現）
/// 実際の PostCard のレイアウトに合わせたミニチュア版
class _PostStylePreview extends StatelessWidget {
  const _PostStylePreview({
    required this.postCardStyle,
    required this.hideUserInfo,
    required this.sensitiveMode,
    required this.imagePreviewSize,
  });

  final PostCardStyle postCardStyle;
  final bool hideUserInfo;
  final SensitiveMode sensitiveMode;
  final ImagePreviewSize imagePreviewSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCard = postCardStyle == PostCardStyle.card;
    final isSensitive = sensitiveMode != SensitiveMode.show;
    // 実際の singleImageMaxHeight に比例したプレビュー高さ
    final imageHeight = switch (imagePreviewSize) {
      ImagePreviewSize.small => 50.0,
      ImagePreviewSize.medium => 80.0,
      ImagePreviewSize.large => 110.0,
    };

    // PostCard と同じ横並びレイアウト（アバター左・コンテンツ右）
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hideUserInfo) ...[
          // 通常モード: アバター
          const CircleAvatar(
            radius: 16,
            backgroundImage: AssetImage('assets/icon.png'),
          ),
          const SizedBox(width: 10),
        ] else ...[
          // 匿名モード: 小さなアイコン
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Opacity(
              opacity: 0.5,
              child: Icon(Icons.public, size: 14, color: Colors.grey[500]),
            ),
          ),
        ],
        // コンテンツ列
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 名前行（通常モードのみ）
              if (!hideUserInfo) ...[
                Row(
                  children: [
                    const Text('ユーザー名',
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 4),
                    Text('@handle',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    const Spacer(),
                    Text('3m',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              // 本文
              const Text(
                'これはプレビュー用の投稿です。設定の変更がリアルタイムに反映されます。',
                style: TextStyle(fontSize: 14, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // 画像エリア（ロゴ画像 + センシティブオーバーレイ）
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: imageHeight,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset('assets/logo.png', fit: BoxFit.cover),
                      if (isSensitive)
                        ClipRRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.1),
                              alignment: Alignment.center,
                              child: Text(
                                'タップで表示',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 匿名モード: 右端にタイムスタンプ
        if (hideUserInfo)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 8),
            child: Text('3m',
                style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ),
      ],
    );

    if (isCard) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:
              BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: content,
        ),
      );
    } else {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: content,
          ),
          Divider(height: 1, thickness: 0.5, color: Colors.grey.withAlpha(40)),
        ],
      );
    }
  }
}
