import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../../models/sns_service.dart';
import '../../providers/settings_provider.dart';
import '../../services/account_storage_service.dart';
import '../post_card.dart';

/// 初回に選ぶタイムラインの見た目。サンプルで見て分かる項目だけを切り替える
class TimelineStylePreset {
  const TimelineStylePreset({
    required this.name,
    this.postCardStyle = PostCardStyle.separator,
    this.fontScale = 1.0,
    this.metaEmphasis = PostMetaEmphasis.subtle,
    this.hideEngagement = false,
  });

  final String name;
  final PostCardStyle postCardStyle;

  /// 設定画面のフォントサイズと同じ値（1.0 が表示上の 125%）
  final double fontScale;
  final PostMetaEmphasis metaEmphasis;
  final bool hideEngagement;

  void apply(SettingsNotifier notifier) {
    notifier
      ..setPostCardStyle(postCardStyle)
      ..setFontScale(fontScale)
      ..setPostMetaEmphasis(metaEmphasis)
      ..setHideEngagement(hideEngagement);
  }
}

/// 先頭がおすすめ。最初から選んだ状態で出す
const timelineStylePresets = [
  TimelineStylePreset(name: '標準'),
  TimelineStylePreset(
    name: 'カード',
    postCardStyle: PostCardStyle.card,
    metaEmphasis: PostMetaEmphasis.normal,
  ),
  TimelineStylePreset(
    name: 'すっきり',
    metaEmphasis: PostMetaEmphasis.faint,
    hideEngagement: true,
  ),
  TimelineStylePreset(name: '大きな文字', fontScale: 1.2),
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
    // ナビゲーションバー（ホームボタン等）の分を空ける。useSafeArea は下を見ない
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('タイムラインの見た目を選ぶ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          for (var i = 0; i < timelineStylePresets.length; i++)
            _PresetTile(
              index: i,
              preset: timelineStylePresets[i],
              selected: i == _selected,
              recommended: i == 0,
              onTap: () => setState(() => _selected = i),
            ),
          const SizedBox(height: 4),
          Text('あとから「設定」でいつでも変えられます。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                timelineStylePresets[_selected]
                    .apply(ref.read(settingsProvider.notifier));
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
    required this.index,
    required this.preset,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  final int index;
  final TimelineStylePreset preset;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: selected ? 0.12 : 0),
            // 太さは変えない。選択で中身の位置がずれる
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
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
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Sample(index: index, preset: preset),
            ],
          ),
        ),
      ),
    );
  }
}

/// 実際の投稿表示（PostCard）でサンプルを描く。作り物のプレビューだと実物とずれる
class _Sample extends StatelessWidget {
  const _Sample({required this.index, required this.preset});

  final int index;
  final TimelineStylePreset preset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 見本の投稿者は自分のアカウントを借りる（アイコンが無地だと実物らしく見えない）
    final accounts = AccountStorageService.instance.accounts;
    final me = accounts.isNotEmpty ? accounts.first : null;
    final post = Post(
      // Hero のタグが投稿 ID から作られるので、見本ごとに分ける
      id: 'onboarding_sample_$index',
      source: me?.service ?? SnsService.x,
      username: me?.displayName ?? 'OmniVerse',
      handle: me?.handle ?? '@omniverse',
      avatarUrl: me?.avatarUrl,
      body: 'お昼はカレーにしました。思ったより辛かったけど、おいしかった！',
      timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
      replyCount: 2,
      repostCount: 5,
      likeCount: 24,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: scheme.surface,
        // 見本の中は押しても何も起きないようにする（プロフィールに飛ぶなど）
        child: IgnorePointer(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(preset.fontScale),
            ),
            child: PostCard(
              post: post,
              useSeparatorStyle:
                  preset.postCardStyle == PostCardStyle.separator,
              metaEmphasis: preset.metaEmphasis,
              hideEngagement: preset.hideEngagement,
            ),
          ),
        ),
      ),
    );
  }
}
