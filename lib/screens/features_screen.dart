import 'package:flutter/material.dart';

import '../services/x_features.dart';
import '../services/x_features_service.dart';

class FeaturesScreen extends StatelessWidget {
  const FeaturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cached = XFeaturesService.instance.currentCache;
    final allOps = [
      'HomeLatestTimeline', 'TweetDetail', 'UserTweets', 'UserMedia',
      'NotificationsTimeline', 'UserByScreenName', 'CreateTweet',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('features 管理')),
      body: ListView(
        children: [
          for (final op in allOps) ...[
            _FeaturesTile(
              operationName: op,
              cached: cached[op],
              resolved: XFeatures.forOperation(op),
              isCached: cached.containsKey(op),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeaturesTile extends StatelessWidget {
  const _FeaturesTile({
    required this.operationName,
    required this.cached,
    required this.resolved,
    required this.isCached,
  });

  final String operationName;
  final Map<String, dynamic>? cached;
  final Map<String, dynamic> resolved;
  final bool isCached;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(
        isCached ? Icons.cloud_done : Icons.code,
        size: 18,
        color: isCached ? Colors.green : Colors.orange,
      ),
      title: Text(operationName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      subtitle: Text(
        isCached ? 'WebViewから取得 (${resolved.length}キー)' : 'ハードコード定義 (${resolved.length}キー)',
        style: TextStyle(fontSize: 11, color: isCached ? Colors.green : Colors.orange),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in resolved.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(entry.key, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                      ),
                      Text(
                        '${entry.value}',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: entry.value == true ? Colors.green : entry.value == false ? Colors.red : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
