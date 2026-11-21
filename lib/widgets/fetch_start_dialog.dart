import 'package:flutter/material.dart';

import '../utils/number_format.dart';

/// 開始ダイアログの「対象」の 1 つ
class FetchTargetChoice {
  const FetchTargetChoice(this.key, this.label, {this.count, this.enabled = true});

  final String key;
  final String label;

  /// 添える人数。null なら出さない
  final int? count;

  /// まだ一覧が無いなど、選べないときは false
  final bool enabled;
}

/// 「内容」のオンオフ 1 つ
class FetchOption {
  const FetchOption(this.label, {required this.value, this.onChanged});

  final String label;
  final bool value;

  /// null なら押せない
  final ValueChanged<bool>? onChanged;
}

/// 取得・つながり調査・詳しい情報の開始ダイアログに共通の枠。
///
/// 並びは「対象 → 内容 → 要約 1 行 → キャンセル／開始」で固定する。
/// 中身だけがスクロールし、開始ボタンは横向きでも常に見えている。
/// 選択肢の説明は置かない。細かい決まりは各まとまりの ⓘ に任せる
class FetchStartDialog extends StatelessWidget {
  const FetchStartDialog({
    super.key,
    required this.title,
    required this.targets,
    required this.selected,
    required this.onSelected,
    this.optionsLabel,
    this.options = const [],
    required this.summary,
    required this.onStart,
  });

  final String title;
  final List<FetchTargetChoice> targets;
  final String selected;
  final ValueChanged<String> onSelected;

  /// 「内容」の見出し。options が空なら出さない
  final String? optionsLabel;
  final List<FetchOption> options;

  /// 人数・目安・容量などを 1 行で
  final Widget summary;

  /// null なら開始できない
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heading = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: scheme.onSurfaceVariant);

    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      // 選択肢だけをスクロールさせ、要約の 1 行は開始ボタンの上に固定する。
      // 横向きは縦が狭く、要約まで一緒に流れると選んだ結果が見えない
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('対象', style: heading),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in targets)
                        ChoiceChip(
                          label: Text(t.count == null
                              ? t.label
                              : '${t.label} ${formatNumber(t.count!)}'),
                          selected: t.key == selected,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: t.enabled ? (_) => onSelected(t.key) : null,
                        ),
                    ],
                  ),
                  if (options.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(optionsLabel ?? '内容', style: heading),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final o in options)
                          FilterChip(
                            label: Text(o.label),
                            selected: o.value,
                            visualDensity: VisualDensity.compact,
                            onSelected: o.onChanged,
                          ),
                ],
              ),
            ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DefaultTextStyle.merge(
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            child: summary,
          ),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: onStart,
          child: const Text('開始'),
        ),
      ],
    );
  }
}
