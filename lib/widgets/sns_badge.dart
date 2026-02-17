import 'package:flutter/material.dart';

import '../models/sns_service.dart';

class SnsBadge extends StatelessWidget {
  const SnsBadge({super.key, required this.service});

  final SnsService service;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (service) {
      SnsService.x => (Colors.black, Colors.white),
      SnsService.bluesky => (const Color(0xFF0085FF), Colors.white),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        service.label,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
