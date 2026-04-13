import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_omniverse/services/x_features_service.dart';

void main() {
  group('XFeaturesService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getFeatures returns null when not cached', () async {
      final svc = XFeaturesService.instance;
      await svc.clearCache();
      await svc.init();
      expect(svc.getFeatures('HomeLatestTimeline'), isNull);
    });

    test('updateFeatures stores and retrieves features', () async {
      final svc = XFeaturesService.instance;
      await svc.clearCache();
      await svc.init();
      await svc.updateFeatures('HomeLatestTimeline', {'key1': true, 'key2': false});
      final result = svc.getFeatures('HomeLatestTimeline');
      expect(result, isNotNull);
      expect(result!['key1'], true);
      expect(result['key2'], false);
    });

    test('clearCache removes all features', () async {
      final svc = XFeaturesService.instance;
      await svc.clearCache();
      await svc.init();
      await svc.updateFeatures('TestOp', {'a': true});
      await svc.clearCache();
      expect(svc.getFeatures('TestOp'), isNull);
      expect(svc.currentCache, isEmpty);
    });
  });
}
