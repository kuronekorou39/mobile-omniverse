import 'package:flutter/material.dart';

import '../models/sns_service.dart';

class SnsBadge extends StatelessWidget {
  const SnsBadge({super.key, required this.service, this.size});

  final SnsService service;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final fontSize = size ?? 10.0;
    final hPad = fontSize < 10 ? 4.0 : 6.0;
    final vPad = fontSize < 10 ? 1.0 : 2.0;

    final (Color bg, Color fg) = switch (service) {
      SnsService.x => (Colors.black, Colors.white),
      SnsService.bluesky => (const Color(0xFF0085FF), Colors.white),
    };

    final String text = switch (service) {
      SnsService.x => '\u{1D54F}',
      SnsService.bluesky => '\u{1F98B}',
    };

    final textStyle = switch (service) {
      SnsService.x => TextStyle(color: fg, fontSize: fontSize, fontWeight: FontWeight.bold),
      SnsService.bluesky => TextStyle(color: fg, fontSize: fontSize),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: textStyle,
      ),
    );
  }
}
