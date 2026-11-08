import 'package:flutter/material.dart';

/// 「@ID の履歴」のような AppBar のタイトル。
///
/// @ID を先に書くと、長い ID で画面名のほうが見切れて、どの画面か
/// 分からなくなる。画面名を上に、@ID を下に小さく出す。
class TargetTitle extends StatelessWidget {
  const TargetTitle(this.title, {super.key, required this.handle});

  /// 画面名（「履歴」「誕生日」など）
  final String title;

  /// 対象の @ID（@ は付けずに渡す）
  final String handle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        Text('@$handle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
