import 'package:flutter/material.dart';

/// 対象画面のまとまりに付ける小見出し。
///
/// まとまりごとに面の色や枠を変えると画面が散らかるので、区切りは
/// この見出しと余白だけで付ける。
class FollowSectionHeader extends StatelessWidget {
  const FollowSectionHeader(
    this.title, {
    super.key,
    this.info,
    this.expanded,
    this.onToggle,
    this.summary,
  });

  /// まとまり同士の間隔
  static const sectionGap = 28.0;

  final String title;

  /// 常時読む必要のない説明。info アイコンに畳む
  final String? info;

  /// 開閉できるまとまりなら、今開いているか。null なら開閉しない
  final bool? expanded;
  final VoidCallback? onToggle;

  /// 閉じているときに見出しの右に出す一言（件数など）
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final open = expanded;
    final row = Row(
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: scheme.onSurfaceVariant)),
        if (info case final message?) ...[
          const SizedBox(width: 6),
          Tooltip(
            triggerMode: TooltipTriggerMode.tap,
            // 数行の説明なので、既定の 1.5 秒では読み終わらない。
            // 外を押せばその場で消える
            showDuration: const Duration(seconds: 10),
            message: message,
            child: Icon(Icons.info_outline,
                size: 16, color: scheme.onSurfaceVariant),
          ),
        ],
        if (open != null) ...[
          const Spacer(),
          if (!open && summary != null)
            Text(summary!,
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.expand_more,
                size: 20, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );

    if (open == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: row,
      );
    }
    // 開閉する見出しは、行全体を押せるようにする（矢印だけだと小さい）
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: row,
        ),
      ),
    );
  }
}
