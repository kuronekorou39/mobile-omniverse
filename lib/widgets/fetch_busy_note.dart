import 'package:flutter/material.dart';

import '../services/fetch_jobs.dart';

/// 別の取得が走っていて、ここからは始められないことを示す。
///
/// 取得は 1 本ずつしか走らせない（[FetchJobs]）。開始ボタンを押せなく
/// するだけだと理由が分からないので、何が走っているかを添える。
/// 同じグルグルを出すと、ここが動いているように見えるので出さない。
class FetchBusyNote extends StatelessWidget {
  const FetchBusyNote(this.running, {super.key});

  final RunningFetch running;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${running.title} を実行中',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  '取得は 1 つずつ動きます。終わるか止めるまで、ここからは始められません',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
