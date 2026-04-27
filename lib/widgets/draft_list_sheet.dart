import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/draft_list_provider.dart';
import '../services/draft_service.dart';

/// 下書き一覧を表示する BottomSheet。
/// 項目タップで [onPick] が呼ばれる（呼び出し側で Compose を再構成する）。
class DraftListSheet extends ConsumerWidget {
  const DraftListSheet({super.key, required this.onPick});

  final void Function(Draft draft) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(draftListProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '下書き',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  asyncList.maybeWhen(
                    data: (list) => Text(
                      '${list.length} 件',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: asyncList.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('読み込みエラー: $e'),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('下書きはありません',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: theme.dividerColor),
                    itemBuilder: (ctx, i) {
                      final draft = list[i];
                      return _DraftRow(
                        draft: draft,
                        onTap: () => onPick(draft),
                        onDelete: () => ref
                            .read(draftListProvider.notifier)
                            .delete(draft.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.draft,
    required this.onTap,
    required this.onDelete,
  });

  final Draft draft;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = draft.text.length > 60
        ? '${draft.text.substring(0, 60)}…'
        : draft.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (draft.isFailureDraft) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Icon(
                  Icons.error_outline,
                  size: 16,
                  color: Colors.red.shade700,
                ),
              ),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.isEmpty ? '(空のテキスト)' : preview,
                    style: TextStyle(
                      fontSize: 14,
                      color: preview.isEmpty
                          ? theme.colorScheme.onSurfaceVariant
                          : null,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _relativeTime(draft.updatedAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (draft.inReplyToPost != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'リプライ',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                      if (draft.quotedPost != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '引用',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              iconSize: 20,
              onPressed: onDelete,
              tooltip: '削除',
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime updatedAt) {
    final diff = DateTime.now().difference(updatedAt);
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分前';
    if (diff.inHours < 24) return '${diff.inHours} 時間前';
    if (diff.inDays < 7) return '${diff.inDays} 日前';
    final m = updatedAt.month.toString().padLeft(2, '0');
    final d = updatedAt.day.toString().padLeft(2, '0');
    return '$m/$d';
  }
}
