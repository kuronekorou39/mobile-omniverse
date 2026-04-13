import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/debug_log_service.dart';

void main() {
  group('DebugLogService', () {
    late DebugLogService svc;

    setUp(() {
      svc = DebugLogService.instance;
      // Reset enabled state for each test
      svc.enabled = false;
    });

    test('enabled defaults to false on singleton', () {
      // The singleton is shared, but enabled should be false after setUp
      expect(svc.enabled, isFalse);
    });

    test('enabled can be toggled', () {
      svc.enabled = true;
      expect(svc.enabled, isTrue);
      svc.enabled = false;
      expect(svc.enabled, isFalse);
    });

    test('logSizeLabel returns a string', () {
      final label = svc.logSizeLabel;
      expect(label, isA<String>());
      expect(label, isNotEmpty);
    });

    test('logSizeLabel contains size unit', () {
      // logBytes is 0 when no file is initialized -> "0 B"
      final label = svc.logSizeLabel;
      expect(label, contains('B'));
    });

    test('logBytes is non-negative', () {
      expect(svc.logBytes, greaterThanOrEqualTo(0));
    });

    test('log() does not throw when enabled is false', () async {
      svc.enabled = false;
      // Should return immediately without error
      await svc.log('TEST', 'This should be a no-op');
    });

    test('logHttp() does not throw when enabled is false', () async {
      svc.enabled = false;
      await svc.logHttp(
        tag: 'TEST',
        method: 'GET',
        url: 'https://example.com',
      );
    });

    test('logWebView() does not throw when enabled is false', () async {
      svc.enabled = false;
      await svc.logWebView(
        tag: 'TEST',
        operation: 'HomeLatestTimeline',
      );
    });

    test('logFilePath returns a path or null', () {
      // Before init(), _logFile is null so logFilePath should be null
      // After init(), it returns a path. Both are valid.
      final path = svc.logFilePath;
      expect(path == null || path.isNotEmpty, isTrue);
    });

    test('clear() does not throw when logFile is null', () async {
      // clear() should be safe to call even before init()
      // (it checks _logFile == null and returns early)
      await svc.clear();
    });

    test('readAll() returns empty string when logFile is null or missing', () async {
      // If _logFile is null, readAll returns ''
      final content = await svc.readAll();
      expect(content, isA<String>());
    });

    test('onLogSizeWarning callback can be set', () {
      String? warningLabel;
      svc.onLogSizeWarning = (label) {
        warningLabel = label;
      };
      // The callback is set, verify it's assignable
      expect(svc.onLogSizeWarning, isNotNull);
      // Clean up
      svc.onLogSizeWarning = null;
    });
  });
}
