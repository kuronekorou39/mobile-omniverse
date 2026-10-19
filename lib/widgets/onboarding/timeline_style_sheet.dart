import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../screens/settings/post_display_settings_screen.dart'
    show PostStylePreview;

/// 初回に選ぶタイムラインの見た目。設定のいくつかをまとめて切り替える
class TimelineStylePreset {
  const TimelineStylePreset({
    required this.name,
    required this.description,
    required this.icon,
    this.imagePreviewSize = ImagePreviewSize.medium,
    this.metaEmphasis = PostMetaEmphasis.subtle,
    this.hideEngagement = false,
    this.hideUserInfo = false,
    this.sensitiveMode = SensitiveMode.hide,
  });

  final String name;
  final String description;
  final IconData icon;
  final ImagePreviewSize imagePreviewSize;
  final PostMetaEmphasis metaEmphasis;
  final bool hideEngagement;
  final bool hideUserInfo;
  final SensitiveMode sensitiveMode;

  void apply(SettingsNotifier notifier) {
    notifier
      ..setPostCardStyle(PostCardStyle.separator)
      ..setImagePreviewSize(imagePreviewSize)
      ..setPostMetaEmphasis(metaEmphasis)
      ..setHideEngagement(hideEngagement)
      ..setHideUserInfo(hideUserInfo)
      ..setSensitiveMode(sensitiveMode);
  }
}

/// 先頭がおすすめ。最初から選んだ状態で出す
const timelineStylePresets = [
  TimelineStylePreset(
    name: 'バランス',
    description: '迷ったらこれ。読みやすさと操作のしやすさのバランス型',
    icon: Icons.auto_awesome_outlined,
  ),
  TimelineStylePreset(
    name: 'すっきり読む',
    description: 'いいね・RT のボタンを隠して、文章に集中',
    icon: Icons.menu_book_outlined,
    imagePreviewSize: ImagePreviewSize.small,
    metaEmphasis: PostMetaEmphasis.faint,
    hideEngagement: true,
  ),
  TimelineStylePreset(
    name: '画像を大きく',
    description: '写真やイラストを大きく表示',
    icon: Icons.photo_outlined,
    imagePreviewSize: ImagePreviewSize.large,
  ),
  TimelineStylePreset(
    name: '人前で見る',
    description: '名前とアイコンを隠し、画像もすべてぼかす',
    icon: Icons.visibility_off_outlined,
    hideUserInfo: true,
    sensitiveMode: SensitiveMode.hideAll,
  ),
];

Future<void> showTimelineStyleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _TimelineStyleSheet(),
  );
}

class _TimelineStyleSheet extends ConsumerStatefulWidget {
  const _TimelineStyleSheet();

  @override
  ConsumerState<_TimelineStyleSheet> createState() =>
      _TimelineStyleSheetState();
}

class _TimelineStyleSheetState extends ConsumerState<_TimelineStyleSheet> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preset = timelineStylePresets[_selected];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('タイムラインの見た目を選ぶ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('読み込みが終わりました。好みに近いものを選んでください',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          // 選んだパターンの見え方をその場で見せる
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: scheme.surfaceContainerLow,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: PostStylePreview(
                  postCardStyle: PostCardStyle.separator,
                  hideUserInfo: preset.hideUserInfo,
                  sensitiveMode: preset.sensitiveMode,
                  imagePreviewSize: preset.imagePreviewSize,
                  metaEmphasis: preset.metaEmphasis,
                  hideEngagement: preset.hideEngagement,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < timelineStylePresets.length; i++)
            _PresetTile(
              preset: timelineStylePresets[i],
              selected: i == _selected,
              recommended: i == 0,
              onTap: () => setState(() => _selected = i),
            ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'あとから「設定 → 投稿の表示」でいつでも変えられます。'
                  '文字の濃さやフォントなど、パターン以外の細かい調整もできます。',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                preset.apply(ref.read(settingsProvider.notifier));
                Navigator.of(context).pop();
              },
              child: const Text('これにする'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  final TimelineStylePreset preset;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: selected ? 0.12 : 0),
            // 太さは変えない。選択で中身の位置がずれる
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(preset.icon,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(preset.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        if (recommended) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('おすすめ',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onPrimaryContainer)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(preset.description,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
