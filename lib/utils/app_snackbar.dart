import 'package:flutter/material.dart';

enum SnackType { success, error, warning, info }

/// 統一されたSnackBar表示
void showAppSnackBar(
  BuildContext context,
  String message, {
  SnackType type = SnackType.info,
  Duration? duration,
  SnackBarAction? action,
}) {
  final (icon, color) = switch (type) {
    SnackType.success => (Icons.check_circle_outline, Colors.green),
    SnackType.error => (Icons.error_outline, Colors.redAccent),
    SnackType.warning => (Icons.warning_amber_outlined, Colors.orange),
    SnackType.info => (Icons.info_outline, Colors.white70),
  };

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      duration: duration ?? const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      action: action,
    ),
  );
}
