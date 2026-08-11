import 'package:flutter/material.dart';

/// はい/いいえの確認ダイアログ。確定なら true。
///
/// **pop には builder が渡す `ctx` を使うこと。**
/// このアプリはタブごとに入れ子の Navigator を持つ (HomeScreen)。
/// showDialog は既定で **ルート** Navigator に載るのに対し、呼び出し元画面の
/// context から引ける Navigator は **タブの** Navigator なので、画面の context で
/// pop するとダイアログではなくその画面自体が閉じ、戻り値が null になる。
/// 「確認したのに何も起きない」の正体がこれ。
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String cancelLabel = 'キャンセル',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: Colors.red)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
