import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_omniverse/services/x_features.dart';
import 'package:mobile_omniverse/services/x_features_service.dart';

void main() {
  group('XFeatures.timeline', () {
    test('is non-empty Map', () {
      expect(XFeatures.timeline, isA<Map<String, dynamic>>());
      expect(XFeatures.timeline, isNotEmpty);
    });

    test('contains expected keys', () {
      expect(XFeatures.timeline.containsKey('rweb_tipjar_consumption_enabled'), isTrue);
      expect(XFeatures.timeline.containsKey('responsive_web_graphql_exclude_directive_enabled'), isTrue);
      expect(XFeatures.timeline.containsKey('verified_phone_label_enabled'), isTrue);
      expect(XFeatures.timeline.containsKey('view_counts_everywhere_api_enabled'), isTrue);
      expect(XFeatures.timeline.containsKey('longform_notetweets_consumption_enabled'), isTrue);
    });
  });

  group('XFeatures.userProfile', () {
    test('is non-empty Map', () {
      expect(XFeatures.userProfile, isA<Map<String, dynamic>>());
      expect(XFeatures.userProfile, isNotEmpty);
    });

    test('contains expected keys', () {
      expect(XFeatures.userProfile.containsKey('hidden_profile_subscriptions_enabled'), isTrue);
      expect(XFeatures.userProfile.containsKey('responsive_web_graphql_timeline_navigation_enabled'), isTrue);
    });
  });

  group('XFeatures.createTweet', () {
    test('is non-empty Map', () {
      expect(XFeatures.createTweet, isA<Map<String, dynamic>>());
      expect(XFeatures.createTweet, isNotEmpty);
    });

    test('contains expected keys', () {
      expect(XFeatures.createTweet.containsKey('responsive_web_edit_tweet_api_enabled'), isTrue);
      expect(XFeatures.createTweet.containsKey('premium_content_api_read_enabled'), isTrue);
    });
  });

  group('XFeatures.forOperation (no cache)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await XFeaturesService.instance.clearCache();
      await XFeaturesService.instance.init();
    });

    test('HomeLatestTimeline returns timeline features', () {
      final result = XFeatures.forOperation('HomeLatestTimeline');
      expect(result, equals(XFeatures.timeline));
    });

    test('UserByScreenName returns userProfile features', () {
      final result = XFeatures.forOperation('UserByScreenName');
      expect(result, equals(XFeatures.userProfile));
    });

    test('CreateTweet returns createTweet features', () {
      final result = XFeatures.forOperation('CreateTweet');
      expect(result, equals(XFeatures.createTweet));
    });

    test('TweetDetail returns timeline features', () {
      final result = XFeatures.forOperation('TweetDetail');
      expect(result, equals(XFeatures.timeline));
    });

    test('NotificationsTimeline returns timeline features', () {
      final result = XFeatures.forOperation('NotificationsTimeline');
      expect(result, equals(XFeatures.timeline));
    });

    test('UserTweets returns timeline features', () {
      final result = XFeatures.forOperation('UserTweets');
      expect(result, equals(XFeatures.timeline));
    });

    test('UserMedia returns timeline features', () {
      final result = XFeatures.forOperation('UserMedia');
      expect(result, equals(XFeatures.timeline));
    });

    test('UnknownOp returns timeline features as default', () {
      final result = XFeatures.forOperation('UnknownOp');
      expect(result, equals(XFeatures.timeline));
    });
  });

  group('XFeatures.forOperation (with cache)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await XFeaturesService.instance.clearCache();
      await XFeaturesService.instance.init();
    });

    tearDown(() async {
      await XFeaturesService.instance.clearCache();
    });

    test('returns cached features when available', () async {
      await XFeaturesService.instance.updateFeatures(
        'HomeLatestTimeline',
        {'custom_key': true},
      );
      final result = XFeatures.forOperation('HomeLatestTimeline');
      expect(result['custom_key'], true);
      expect(result.containsKey('rweb_tipjar_consumption_enabled'), isFalse);
    });

    test('cached features override hardcoded defaults', () async {
      await XFeaturesService.instance.updateFeatures(
        'UserByScreenName',
        {'overridden': 'yes', 'count': 42},
      );
      final result = XFeatures.forOperation('UserByScreenName');
      expect(result['overridden'], 'yes');
      expect(result['count'], 42);
      expect(result.containsKey('hidden_profile_subscriptions_enabled'), isFalse);
    });

    test('non-cached operations still return hardcoded defaults', () async {
      await XFeaturesService.instance.updateFeatures(
        'HomeLatestTimeline',
        {'custom_key': true},
      );
      // TweetDetail is NOT cached, should still return hardcoded timeline
      final result = XFeatures.forOperation('TweetDetail');
      expect(result, equals(XFeatures.timeline));
    });
  });
}
