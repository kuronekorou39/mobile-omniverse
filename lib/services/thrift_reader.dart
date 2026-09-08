import 'dart:convert';
import 'dart:typed_data';

/// Thrift Binary Protocol の読み取り。
///
/// XChat のメッセージは Base64 の Thrift として届く。必要なのは
/// 「フィールド番号 → 値」の対応だけなので、スキーマは持たず
/// 素直に Map<int, dynamic> として読む。
///
/// 型の対応:
///   2=bool(値1バイト) 3=byte 4=double 6=i16 8=i32 10=i64
///   11=string/binary 12=struct 15=list
class ThriftReader {
  ThriftReader(this._d, [this._i = 0]);

  factory ThriftReader.fromBase64(String b64) =>
      ThriftReader(ByteData.sublistView(base64.decode(b64)));

  final ByteData _d;
  int _i;

  static const _stop = 0;
  static const _bool = 2;
  static const _byte = 3;
  static const _double = 4;
  static const _i16 = 6;
  static const _i32 = 8;
  static const _i64 = 10;
  static const _string = 11;
  static const _struct = 12;
  static const _list = 15;
  static const _set = 14;

  /// 1 つの構造体を読み、フィールド番号をキーにした Map で返す。
  /// 読めないところに当たったら、そこまでの分を返す（落とさない）
  Map<int, dynamic> readStruct({int depth = 0}) {
    final out = <int, dynamic>{};
    while (_i < _d.lengthInBytes) {
      final type = _d.getUint8(_i);
      _i++;
      if (type == _stop) break;
      if (_i + 2 > _d.lengthInBytes) break;
      final fid = _d.getInt16(_i);
      _i += 2;
      final value = _readValue(type, depth);
      if (value == _unreadable) break;
      out[fid] = value;
    }
    return out;
  }

  static const _unreadable = Object();

  Object? _readValue(int type, int depth) {
    switch (type) {
      case _bool:
        final v = _d.getUint8(_i) != 0;
        _i += 1;
        return v;
      case _byte:
        final v = _d.getInt8(_i);
        _i += 1;
        return v;
      case _double:
        final v = _d.getFloat64(_i);
        _i += 8;
        return v;
      case _i16:
        final v = _d.getInt16(_i);
        _i += 2;
        return v;
      case _i32:
        final v = _d.getInt32(_i);
        _i += 4;
        return v;
      case _i64:
        final v = _d.getInt64(_i);
        _i += 8;
        return v;
      case _string:
        final len = _d.getInt32(_i);
        _i += 4;
        if (len < 0 || _i + len > _d.lengthInBytes) return _unreadable;
        final raw =
            _d.buffer.asUint8List(_d.offsetInBytes + _i, len);
        _i += len;
        // 文字列か生バイトかは呼ぶ側で決める。UTF-8 で読めれば文字列
        return Uint8List.fromList(raw);
      case _struct:
        // 深すぎる入れ子は追わない（壊れた入力で無限に潜らないため）
        if (depth > 12) return _unreadable;
        return readStruct(depth: depth + 1);
      case _list:
      case _set:
        final et = _d.getUint8(_i);
        final size = _d.getInt32(_i + 1);
        _i += 5;
        if (size < 0 || size > 100000) return _unreadable;
        final items = <Object?>[];
        for (var n = 0; n < size; n++) {
          final v = _readValue(et, depth + 1);
          if (v == _unreadable) return items;
          items.add(v);
        }
        return items;
      default:
        return _unreadable;
    }
  }

  /// バイト列を UTF-8 として読む。読めなければ null。
  ///
  /// 入れ子の Thrift も、たまたま UTF-8 として通ってしまうことがある
  /// （フィールドヘッダが ASCII の範囲に収まるため）。本文と取り違えると
  /// 制御文字混じりの文字列を画面に出すことになるので、**制御文字を
  /// 含むものは文字列として扱わない**。改行とタブは本文にあり得るので許す。
  static String? asText(Object? value) {
    if (value is! Uint8List) return null;
    String s;
    try {
      s = utf8.decode(value);
    } catch (_) {
      return null;
    }
    for (final c in s.codeUnits) {
      final isAllowedWhitespace = c == 0x09 || c == 0x0A || c == 0x0D;
      if (c < 0x20 && !isAllowedWhitespace) return null;
      if (c == 0x7F) return null;
    }
    return s;
  }

  /// 数字だけの文字列として読む（ID 用）
  static String? asId(Object? value) {
    final s = asText(value);
    if (s == null) return null;
    return s.isEmpty ? null : s;
  }

  /// バイト列を入れ子の Thrift として読む。読めなければ null
  static Map<int, dynamic>? asStruct(Object? value) {
    if (value is Map<int, dynamic>) return value;
    if (value is! Uint8List || value.isEmpty) return null;
    try {
      return ThriftReader(ByteData.sublistView(value)).readStruct();
    } catch (_) {
      return null;
    }
  }
}
