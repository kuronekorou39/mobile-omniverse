import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/engagement_service.dart';
import '../helpers/test_data.dart';

void main() {
  group('EngagementService', () {
    test('postSummary truncates long body with ellipsis', () {
      final post = makePost(body: 'A' * 100);
      final summary = EngagementService.postSummary(post);
      expect(summary.length, 41); // 40 chars + ellipsis
      expect(summary.endsWith('…'), true);
    });

    test('postSummary returns full body when short', () {
      final post = makePost(body: 'Short body');
      final summary = EngagementService.postSummary(post);
      expect(summary, 'Short body');
    });
  });
}
