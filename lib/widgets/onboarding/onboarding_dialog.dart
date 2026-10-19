import 'package:flutter/material.dart';

/// 説明ダイアログの 1 項目
typedef OnboardingItem = ({IconData icon, String title, String body});

/// 初回の説明ダイアログ。見出し + 項目の箇条書き + ボタン 1 つ
Future<void> showOnboardingDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? lead,
  required List<OnboardingItem> items,
  String buttonLabel = 'OK',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(icon, color: scheme.primary, size: 32),
        title: Text(title, textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lead != null) ...[
                Text(lead, style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 16),
              ],
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.icon, size: 22, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(item.body,
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(buttonLabel),
          ),
        ],
      );
    },
  );
}
