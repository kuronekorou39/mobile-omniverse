import 'package:flutter/material.dart';

import '../utils/number_format.dart';

/// 開始ダイアログの「対象」の 1 行
class FetchTargetChoice {
  const FetchTargetChoice(
    this.key,
    this.label, {
    this.count,
    this.unit = '人',
    this.detail,
    this.enabled = true,
  });

  final String key;
  final String label;

  /// 件数。null なら空ける（数え中・数えられないとき）
  final int? count;
  final String unit;

  /// 右端に出す所要時間など。null なら空ける
  final String? detail;

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
/// 並びは「対象（数と時間の表）→ 内容 → 要約 1 行 → キャンセル／開始」で固定する。
/// 中身だけがスクロールし、開始ボタンは横向きでも常に見えている。
/// 選択肢の説明は置かない。細かい決まりは各まとまりの ⓘ に任せる
class FetchStartDialog extends StatelessWidget {
  const FetchStartDialog({
    super.key,
    required this.title,
    required this.targets,
    required this.selected,
    required this.onSelected,
    this.targetsNote,
    this.optionsLabel,
    this.options = const [],
    this.summary,
    required this.onStart,
  });

  final String title;
  final List<FetchTargetChoice> targets;
  final String selected;
  final ValueChanged<String> onSelected;

  /// 「対象」の見出しの右に添える一言（「前回」など）
  final String? targetsNote;

  /// 「内容」の見出し。options が空なら出さない
  final String? optionsLabel;
  final List<FetchOption> options;

  /// 対象の表に出ないこと（容量など）を 1 行で。null なら出さない
  final Widget? summary;

  /// null なら開始できない
  final VoidCallback? onStart;

  /// 横向きで左右 2 列にしたときの中身の幅
  static const _sideBySideWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heading = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: scheme.onSurfaceVariant);
    final size = MediaQuery.sizeOf(context);
    // 横向きは縦が足りない。対象を左、内容と要約を右に並べてスクロールさせない
    final sideBySide = options.isNotEmpty &&
        size.width > size.height &&
        size.width >= _sideBySideWidth + 120;

    final targetsPart = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('対象', style: heading),
            if (targetsNote != null) ...[
              const SizedBox(width: 8),
              Text(targetsNote!,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        // 数と時間を全部の行で見比べられるよう、表のように縦をそろえる
        RadioGroup<String>(
          groupValue: selected,
          onChanged: (v) {
            if (v != null) onSelected(v);
          },
          child: Column(
            children: [for (final t in targets) _targetRow(context, t)],
          ),
        ),
      ],
    );
    final optionsPart = options.isEmpty
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
          );
    final summaryPart = summary == null
        ? null
        : DefaultTextStyle.merge(
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            child: summary!,
          );

    final Widget content;
    if (sideBySide) {
      content = SizedBox(
        width: _sideBySideWidth,
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: targetsPart),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    optionsPart!,
                    if (summaryPart != null) ...[
                      const SizedBox(height: 16),
                      summaryPart,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // 選択肢だけをスクロールさせ、要約の 1 行は開始ボタンの上に固定する
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  targetsPart,
                  if (optionsPart != null) ...[
                    const SizedBox(height: 16),
                    optionsPart,
                  ],
                ],
              ),
            ),
          ),
          if (summaryPart != null) ...[
            const SizedBox(height: 12),
            summaryPart,
          ],
          const SizedBox(height: 4),
        ],
      );
    }

    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: content,
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

  Widget _targetRow(BuildContext context, FetchTargetChoice t) {
    final scheme = Theme.of(context).colorScheme;
    final color = t.enabled ? null : scheme.onSurface.withValues(alpha: 0.38);
    final sub = TextStyle(fontSize: 13, color: color ?? scheme.onSurfaceVariant);
    return InkWell(
      onTap: t.enabled ? () => onSelected(t.key) : null,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Radio<String>(
            value: t.key,
            enabled: t.enabled,
            visualDensity: VisualDensity.compact,
          ),
          // 狭い画面でも折り返さず、入りきらなければ文字を縮める
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(t.label,
                  maxLines: 1, style: TextStyle(fontSize: 14, color: color)),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              t.count == null ? '' : '${formatNumber(t.count!)}${t.unit}',
              textAlign: TextAlign.right,
              style: sub,
            ),
          ),
          SizedBox(
            width: 84,
            child: Text(
              t.detail ?? '',
              textAlign: TextAlign.right,
              style: sub,
            ),
          ),
        ],
      ),
    );
  }
}
