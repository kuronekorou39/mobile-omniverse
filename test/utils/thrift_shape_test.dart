import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/utils/thrift_shape.dart';

/// テスト用に Thrift バイナリを組み立てる
class _Builder {
  final _b = BytesBuilder();

  void string(int fid, String value) {
    final bytes = utf8.encode(value);
    _b.addByte(11);
    _addI16(fid);
    _addI32(bytes.length);
    _b.add(bytes);
  }

  void i64(int fid) {
    _b.addByte(10);
    _addI16(fid);
    _b.add(Uint8List(8));
  }

  void structStart(int fid) {
    _b.addByte(12);
    _addI16(fid);
  }

  void listOfStructStart(int fid, int size) {
    _b.addByte(15);
    _addI16(fid);
    _b.addByte(12);
    _addI32(size);
  }

  void stop() => _b.addByte(0);

  void _addI16(int v) {
    final d = ByteData(2)..setInt16(0, v);
    _b.add(d.buffer.asUint8List());
  }

  void _addI32(int v) {
    final d = ByteData(4)..setInt32(0, v);
    _b.add(d.buffer.asUint8List());
  }

  String get base64Value => base64.encode(_b.toBytes());
}

void main() {
  group('文字列の種類を見分ける', () {
    test('数字・UUID・URL・本文を分ける', () {
      expect(ThriftShape.classify(utf8.encode('1007833643987812356')),
          'digits(19)');
      expect(
          ThriftShape.classify(
              utf8.encode('b9af78fa-8827-401d-a75b-25039ef55f3b')),
          'UUID');
      expect(ThriftShape.classify(utf8.encode('742212954:742212954')), 'id:id');
      expect(ThriftShape.classify(utf8.encode('https://ton.x.com/a.jpg')),
          startsWith('URL('));
      expect(ThriftShape.classify(utf8.encode('こんにちは、お世話になります')),
          'TEXT(14文字)');
    });
  });

  group('構造を読む', () {
    test('平らな構造のフィールド番号と型が出る', () {
      final b = _Builder()
        ..string(1, '1007833643987812356')
        ..string(3, '742212954')
        ..i64(5)
        ..stop();
      final lines = ThriftShape.describeBase64(b.base64Value);
      expect(lines, ['1: digits(19)', '3: digits(9)', '5: i64']);
    });

    test('入れ子とリストをたどる', () {
      final b = _Builder()
        ..structStart(7)
        ..listOfStructStart(3, 1)
        ..string(1, 'やあ')
        ..stop() // list の要素
        ..stop() // struct 7
        ..stop();
      final lines = ThriftShape.describeBase64(b.base64Value);
      expect(lines.join('|'), contains('7: {'));
      expect(lines.join('|'), contains('list<12>[1]'));
      expect(lines.join('|'), contains('TEXT(2文字)'));
    });

    test('壊れていても落ちない', () {
      expect(ThriftShape.describeBase64('!!!notbase64!!!').first,
          startsWith('(読めない'));
    });
  });

  // ここが崩れると DM の本文がログに残る
  group('本文を漏らさない', () {
    test('本文は長さだけになる', () {
      const secret = 'いきなりDM失礼します';
      final b = _Builder()
        ..string(1, secret)
        ..stop();
      final joined = ThriftShape.describeBase64(b.base64Value).join();
      expect(joined.contains(secret), isFalse);
      expect(joined.contains('DM'), isFalse);
      expect(joined, contains('TEXT(11文字)'));
    });

    test('URL の中身も出さない', () {
      final b = _Builder()
        ..string(8, 'https://ton.x.com/i/ton/data/dm/123/456/secret.jpg')
        ..stop();
      final joined = ThriftShape.describeBase64(b.base64Value).join();
      expect(joined.contains('secret.jpg'), isFalse);
      expect(joined, contains('URL('));
    });
  });
}
