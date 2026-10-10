import 'package:flutter/material.dart';

/// 対象画面のまとまりに付ける小見出し。
///
/// まとまりごとに面の色や枠を変えると画面が散らかるので、区切りは
/// この見出しと余白だけで付ける。
class FollowSectionHeader extends StatelessWidget {
  const FollowSectionHeader(this.title, {super.key, this.info});

  /// まとまり同士の間隔
  static const sectionGap = 28.0;

  final String title;

  /// 常時読む必要のない説明。info アイコンに畳む
  final String? info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
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
              message: message,
              child: Icon(Icons.info_outline,
                  size: 16, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
