import 'package:flutter/material.dart';

import 'app_snackbar.dart';

/// エンゲージメントエラーをSnackBarで表示
void showEngagementError(BuildContext context, String action, int? statusCode) {
  showAppSnackBar(context, engagementErrorMessage(action, statusCode),
      type: SnackType.error, duration: const Duration(seconds: 4));
}

/// 後方互換: SnackBar オブジェクトが必要な既存コード用
SnackBar engagementErrorSnackBar(String action, int? statusCode) {
  return SnackBar(
    content: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(engagementErrorMessage(action, statusCode))),
      ],
    ),
    duration: const Duration(seconds: 4),
    behavior: SnackBarBehavior.floating,
  );
}

/// X APIのエラーステータスコードからユーザー向けメッセージを生成
String engagementErrorMessage(String action, int? statusCode) {
  final codeStr = statusCode != null ? ' ($statusCode)' : '';
  final reason = _knownErrors[statusCode];
  if (reason != null) {
    return '$actionに失敗$codeStr: $reason';
  }
  return '$actionに失敗しました$codeStr';
}

const _knownErrors = <int, String>{
  142: '非公開アカウントの投稿です',
  179: '非公開アカウントの投稿です',
  226: '一時的に制限されています（時間を置いて再試行してください）',
  271: 'この投稿をミュートしています',
  327: '既にリツイート済みです',
  328: '非公開アカウントの投稿はリツイートできません',
  344: '操作が許可されていません（非公開投稿の制限の可能性）',
  385: 'リプライ先のリツイートは制限されています',
  403: 'アクセスが拒否されました（アカウント制限の可能性）',
  404: '投稿が見つかりません（削除済みの可能性）',
  429: 'レート制限に達しました（しばらく待ってリトライ）',
};
