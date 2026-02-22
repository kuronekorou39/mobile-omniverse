import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';

/// アプリ更新通知ダイアログを表示
Future<void> showUpdateDialog(BuildContext context, AppUpdateInfo info) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('アップデートがあります'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'v${info.currentVersion} → v${info.latestVersion}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'リリースノート:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  info.releaseNotes,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('後で'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(context).pop();
            final url = Uri.parse(info.downloadUrl);
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('アップデート'),
        ),
      ],
    ),
  );
}
