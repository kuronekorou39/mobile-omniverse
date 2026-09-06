import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/export_service.dart';

void main() {
  final svc = ExportService.instance;

  group('CSV のセル', () {
    test('区切りも引用符も改行も無ければ、そのまま出す', () {
      expect(svc.csvCell('rou39'), 'rou39');
      expect(svc.csvCell(''), '');
      expect(svc.csvCell('日本語もそのまま'), '日本語もそのまま');
    });

    test('カンマを含む値は囲む', () {
      expect(svc.csvCell('東京, 日本'), '"東京, 日本"');
    });

    // プロフィール文に改行はよく入る。囲まないと行がずれて、
    // 表計算で開いたときに全体が壊れる
    test('改行を含む値は囲む', () {
      expect(svc.csvCell('1行目\n2行目'), '"1行目\n2行目"');
      expect(svc.csvCell('CR も\r\n囲む'), '"CR も\r\n囲む"');
    });

    test('引用符は二重にしてから囲む', () {
      expect(svc.csvCell('あだ名は"ろう"'), '"あだ名は""ろう"""');
    });
  });

  group('CSV の行', () {
    test('カンマで連結する', () {
      expect(svc.csvRow(['a', 'b', 'c']), 'a,b,c');
    });

    test('囲みが必要なセルだけ囲まれる', () {
      expect(
        svc.csvRow(['rou39', '東京, 日本', '100']),
        'rou39,"東京, 日本",100',
      );
    });

    test('空のセルも列として残る', () {
      expect(svc.csvRow(['a', '', 'c']), 'a,,c');
    });
  });
}
