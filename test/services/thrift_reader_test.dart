import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/thrift_reader.dart';

/// テスト用に Thrift Binary を組み立てる
class _B {
  final _b = BytesBuilder();

  void str(int fid, String v) {
    final bytes = utf8.encode(v);
    _b.addByte(11);
    _i16(fid);
    _i32(bytes.length);
    _b.add(bytes);
  }

  void raw(int fid, List<int> bytes) {
    _b.addByte(11);
    _i16(fid);
    _i32(bytes.length);
    _b.add(bytes);
  }

  void i64(int fid, int v) {
    _b.addByte(10);
    _i16(fid);
    final d = ByteData(8)..setInt64(0, v);
    _b.add(d.buffer.asUint8List());
  }

  void boolean(int fid, bool v) {
    _b.addByte(2);
    _i16(fid);
    _b.addByte(v ? 1 : 0);
  }

  void structStart(int fid) {
    _b.addByte(12);
    _i16(fid);
  }

  void stop() => _b.addByte(0);

  void _i16(int v) => _b.add((ByteData(2)..setInt16(0, v)).buffer.asUint8List());
  void _i32(int v) => _b.add((ByteData(4)..setInt32(0, v)).buffer.asUint8List());

  Uint8List get bytes => _b.toBytes();
  String get b64 => base64.encode(_b.toBytes());
}

void main() {
  group('基本の読み取り', () {
    test('フィールド番号をキーに値を返す', () {
      final b = _B()
        ..str(1, '1007833643987812356')
        ..str(3, '742212954')
        ..i64(5, 1787041992489)
        ..stop();
      final m = ThriftReader.fromBase64(b.b64).readStruct();
      expect(ThriftReader.asText(m[1]), '1007833643987812356');
      expect(ThriftReader.asText(m[3]), '742212954');
      expect(m[5], 1787041992489);
    });

    // bool は値が 1 バイト続く。読み飛ばさないと以降が全部ずれる
    test('bool の後のフィールドがずれない', () {
      final b = _B()
        ..boolean(102, true)
        ..i64(104, 42)
        ..boolean(109, false)
        ..stop();
      final m = ThriftReader.fromBase64(b.b64).readStruct();
      expect(m[102], isTrue);
      expect(m[104], 42);
      expect(m[109], isFalse);
    });

    test('入れ子の構造体を読む', () {
      final b = _B()
        ..structStart(7)
        ..structStart(1)
        ..str(100, 'こんにちは')
        ..boolean(102, true)
        ..stop()
        ..stop()
        ..stop();
      final m = ThriftReader.fromBase64(b.b64).readStruct();
      final inner = (m[7] as Map<int, dynamic>)[1] as Map<int, dynamic>;
      expect(ThriftReader.asText(inner[100]), 'こんにちは');
    });
  });

  group('中身の見分け', () {
    test('UTF-8 として読めれば文字列', () {
      final b = _B()..str(1, 'やあ')..stop();
      final m = ThriftReader.fromBase64(b.b64).readStruct();
      expect(ThriftReader.asText(m[1]), 'やあ');
    });

    // 画像のときは同じ位置に入れ子の Thrift が入る
    test('読めないバイト列は入れ子 Thrift として読める', () {
      final inner = _B()
        ..str(6, 'i9ica_Q9.jpg')
        ..stop();
      final outer = _B()
        ..raw(100, inner.bytes)
        ..stop();
      final m = ThriftReader.fromBase64(outer.b64).readStruct();
      final nested = ThriftReader.asStruct(m[100]);
      expect(nested, isNotNull);
      expect(ThriftReader.asText(nested![6]), 'i9ica_Q9.jpg');
    });
  });

  group('壊れた入力', () {
    test('途中で切れていても落ちない', () {
      final full = (_B()..str(1, 'abcdefghij')..stop()).bytes;
      final cut = full.sublist(0, full.length - 5);
      final m = ThriftReader(ByteData.sublistView(cut)).readStruct();
      expect(m, isA<Map<int, dynamic>>());
    });

    test('base64 でなければ例外', () {
      expect(() => ThriftReader.fromBase64('!!!'), throwsA(anything));
    });
  });
}
