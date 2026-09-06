import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/scan_log_service.dart';

void main() {
  group('ScanLogService', () {
    late ScanLogService svc;

    setUp(() {
      svc = ScanLogService.instance;
    });

    test('logBytes は非負', () {
      expect(svc.logBytes, greaterThanOrEqualTo(0));
    });

    test('logSizeLabel は単位つきの文字列を返す', () {
      final label = svc.logSizeLabel;
      expect(label, isA<String>());
      expect(label, isNotEmpty);
      expect(label, contains('B'));
    });

    // init() は端末のドキュメントディレクトリを使うのでテストでは呼べない。
    // 未初期化のまま呼ばれても落ちないことが、調査中に例外で走査を
    // 止めないための最低条件になる
    test('init 前に log() を呼んでも投げない', () async {
      await svc.log('@someone 完了 100件');
    });

    test('init 前に clear() を呼んでも投げない', () async {
      await svc.clear();
    });

    test('init 前の readAll() は空文字', () async {
      expect(await svc.readAll(), isEmpty);
    });

    test('init 前は logFilePath が null', () {
      expect(svc.logFilePath, isNull);
    });
  });
}
