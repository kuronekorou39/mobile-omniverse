import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_snackbar.dart';

/// 投稿の中のリンクを、行き先を見せて確かめてから外のブラウザで開く。
/// 本文を読んでいる途中の誤タップで、いきなりアプリの外へ飛ばないようにする
Future<void> confirmAndOpenUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final scheme = Theme.of(context).colorScheme;

  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('リンクを開きますか？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行き先はドメインで判断するので、いちばん目立たせる
          Text(
            uri.host,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            url,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            Navigator.of(ctx).pop(false);
            showAppSnackBar(context, 'リンクをコピーしました',
                type: SnackType.success);
          },
          child: const Text('コピー'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('開く'),
        ),
      ],
    ),
  );
  if (open == true) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
