import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

enum SnackType { success, error, warning, info }

/// 画面下に一瞬出す知らせ。アプリ中でこれだけを使う。
///
/// 種類ごとに ColorScheme の「〜Container」で面の色を変え、文字と記号は
/// その上に乗る色（on〜Container）にする。色値を直接書かないので、
/// ライト/ダークやシードの変更にそのまま追従する。
///
/// 前のものが残っていれば差し替える。続けて何度も出たときに、古い知らせが
/// 順番待ちで何秒も居座らないようにするため
void showAppSnackBar(
  BuildContext context,
  String message, {
  SnackType type = SnackType.info,
  Duration? duration,
  SnackBarAction? action,
}) {
  final scheme = Theme.of(context).colorScheme;
  final (icon, bg, fg) = switch (type) {
    SnackType.success => (
        Icons.check_circle_outline,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
    SnackType.error => (
        Icons.error_outline,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    SnackType.warning => (
        Icons.warning_amber_outlined,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
    SnackType.info => (
        Icons.info_outline,
        scheme.inverseSurface,
        scheme.onInverseSurface,
      ),
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: bg,
        content: Row(
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: fg, fontSize: 13, height: 1.3),
              ),
            ),
          ],
        ),
        duration: duration ?? const Duration(seconds: 3),
        action: action == null
            ? null
            : SnackBarAction(
                label: action.label,
                onPressed: action.onPressed,
                textColor: fg,
              ),
      ),
    );
}

/// 例外の文字列は長く、利用者が読んでも意味が取れないことが多い。
/// 1 行に収まる長さに切って添える
String shortError(Object e) {
  final s = '$e'.replaceFirst(RegExp(r'^\w*Exception:\s*'), '');
  return s.length > 80 ? '${s.substring(0, 80)}…' : s;
}

/// 通信が途切れた・つながらないときの例外か。
/// 中身の URL や英語の原因は利用者には意味が無いので、まとめて言い換える
bool isNetworkError(Object e) =>
    e is SocketException ||
    e is http.ClientException ||
    e is TimeoutException ||
    e is HandshakeException;

/// 画面に出す失敗の説明。通信の問題は言い換え、それ以外は短く切る
String describeError(Object e) => isNetworkError(e)
    ? '通信できませんでした。電波の状態を確かめて、もう一度試してください'
    : shortError(e);
