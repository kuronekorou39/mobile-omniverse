import 'dart:convert';
import 'dart:typed_data';

/// Thrift バイナリの「形」だけを取り出す。
///
/// XChat のメッセージは encoded_message_events に Base64 の Thrift として
/// 入っている。JSON ではないので jsonShape では中が見えない。パーサーを
/// 書くにはどのフィールドに何が入るかを知る必要があるが、応答をそのまま
/// 残すと本文がログに残る。ここではフィールド番号と型だけを出し、
/// **文字列の中身は出さない**（種類と長さに置き換える）。
class ThriftShape {
  ThriftShape._();

  static const _stop = 0;
  static const _boolTrue = 1;
  static const _boolFalse = 2;
  static const _byte = 3;
  static const _double = 4;
  static const _i16 = 6;
  static const _i32 = 8;
  static const _i64 = 10;
  static const _string = 11;
  static const _struct = 12;
  static const _map = 13;
  static const _set = 14;
  static const _list = 15;

  /// Base64 の Thrift を読んで、フィールドの形を 1 行ずつ返す
  static List<String> describeBase64(String b64, {int maxDepth = 8}) {
    try {
      final bytes = base64.decode(b64);
      final out = <String>[];
      _readStruct(ByteData.sublistView(bytes), 0, 0, out, maxDepth);
      return out;
    } catch (e) {
      return ['(読めない: $e)'];
    }
  }

  /// 文字列の種類だけを判定する。中身は返さない
  static String classify(List<int> raw) {
    String s;
    try {
      s = utf8.decode(raw);
    } catch (_) {
      return 'bytes(${raw.length})';
    }
    if (RegExp(r'^\d+$').hasMatch(s)) return 'digits(${s.length})';
    if (RegExp(r'^[0-9a-f-]{36}$').hasMatch(s)) return 'UUID';
    if (RegExp(r'^\d+:\d+$').hasMatch(s)) return 'id:id';
    if (s.startsWith('http')) return 'URL(${s.length})';
    if (s.length < 40 && RegExp(r'^[\w.\-]+$').hasMatch(s)) {
      return 'token(${s.length})';
    }
    // ここが本文。長さだけ出す
    return 'TEXT(${s.length}文字)';
  }

  static int _readStruct(
      ByteData d, int i, int depth, List<String> out, int maxDepth) {
    final pad = '  ' * depth;
    while (i < d.lengthInBytes) {
      final type = d.getUint8(i);
      i++;
      if (type == _stop) return i;
      if (i + 2 > d.lengthInBytes) return i;
      final fid = d.getInt16(i);
      i += 2;
      switch (type) {
        case _string:
          final len = d.getInt32(i);
          i += 4;
          if (len < 0 || i + len > d.lengthInBytes) return i;
          final raw = d.buffer.asUint8List(d.offsetInBytes + i, len);
          out.add('$pad$fid: ${classify(raw)}');
          i += len;
        case _i64:
          i += 8;
          out.add('$pad$fid: i64');
        case _double:
          i += 8;
          out.add('$pad$fid: double');
        case _i32:
          i += 4;
          out.add('$pad$fid: i32');
        case _i16:
          i += 2;
          out.add('$pad$fid: i16');
        case _byte:
          i += 1;
          out.add('$pad$fid: byte');
        case _boolTrue:
        case _boolFalse:
          out.add('$pad$fid: bool');
        case _struct:
          out.add('$pad$fid: {');
          if (depth >= maxDepth) {
            out.add('$pad  …');
            return i;
          }
          i = _readStruct(d, i, depth + 1, out, maxDepth);
          out.add('$pad}');
        case _list:
        case _set:
          final et = d.getUint8(i);
          final size = d.getInt32(i + 1);
          i += 5;
          out.add('$pad$fid: list<$et>[$size] {');
          for (var n = 0; n < size; n++) {
            if (et == _struct) {
              i = _readStruct(d, i, depth + 1, out, maxDepth);
            } else if (et == _string) {
              final len = d.getInt32(i);
              i += 4;
              if (len < 0 || i + len > d.lengthInBytes) return i;
              final raw = d.buffer.asUint8List(d.offsetInBytes + i, len);
              out.add('$pad  - ${classify(raw)}');
              i += len;
            } else if (et == _i64) {
              i += 8;
            } else if (et == _i32) {
              i += 4;
            } else {
              out.add('$pad  (要素型 $et は未対応)');
              return i;
            }
          }
          out.add('$pad}');
        case _map:
          out.add('$pad$fid: map ← 未対応で中断');
          return i;
        default:
          out.add('$pad$fid: 型$type ← 未対応で中断');
          return i;
      }
    }
    return i;
  }
}
