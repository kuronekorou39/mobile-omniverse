import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// 添付画像に適用するフィルタプリセット。
enum ImageFilter {
  none,
  bright,
  warm,
  cool,
  mono,
  sepia,
  vivid,
}

extension ImageFilterLabel on ImageFilter {
  String get label {
    switch (this) {
      case ImageFilter.none:
        return 'なし';
      case ImageFilter.bright:
        return '明るく';
      case ImageFilter.warm:
        return '暖色';
      case ImageFilter.cool:
        return '寒色';
      case ImageFilter.mono:
        return 'モノクロ';
      case ImageFilter.sepia:
        return 'セピア';
      case ImageFilter.vivid:
        return 'ビビッド';
    }
  }

  /// プレビュー用のカラーマトリクス（5x4 = 20 個、ColorFilter.matrix と同じ並び）。
  /// プレビューは GPU 上の ColorFiltered で即時適用、保存時に同じ matrix を
  /// CPU で再現してバイト列に焼き込む。
  List<double> get matrix {
    switch (this) {
      case ImageFilter.none:
        return _identity;
      case ImageFilter.bright:
        return _scale(1.15);
      case ImageFilter.warm:
        return _offset(red: 22, green: 8, blue: -16);
      case ImageFilter.cool:
        return _offset(red: -14, green: -4, blue: 22);
      case ImageFilter.mono:
        return _saturate(0.0);
      case ImageFilter.sepia:
        return _sepia;
      case ImageFilter.vivid:
        return _saturate(1.5);
    }
  }

  ColorFilter get colorFilter => ColorFilter.matrix(matrix);
}

const List<double> _identity = [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

List<double> _scale(double s) => [
      s, 0, 0, 0, 0, //
      0, s, 0, 0, 0,
      0, 0, s, 0, 0,
      0, 0, 0, 1, 0,
    ];

List<double> _offset({double red = 0, double green = 0, double blue = 0}) => [
      1, 0, 0, 0, red, //
      0, 1, 0, 0, green,
      0, 0, 1, 0, blue,
      0, 0, 0, 1, 0,
    ];

/// 彩度マトリクス（s=0 でモノクロ、s=1 で変化なし、s>1 で彩度UP）
List<double> _saturate(double s) {
  // 標準的な BT.601 luminance 重み
  const lumR = 0.299;
  const lumG = 0.587;
  const lumB = 0.114;
  final invS = 1.0 - s;
  return [
    lumR * invS + s, lumG * invS, lumB * invS, 0, 0, //
    lumR * invS, lumG * invS + s, lumB * invS, 0, 0,
    lumR * invS, lumG * invS, lumB * invS + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

const List<double> _sepia = [
  0.393, 0.769, 0.189, 0, 0, //
  0.349, 0.686, 0.168, 0, 0,
  0.272, 0.534, 0.131, 0, 0,
  0, 0, 0, 1, 0,
];

class ImageFilterService {
  ImageFilterService._();
  static final instance = ImageFilterService._();

  /// バイナリ画像にフィルタを適用して JPEG として返す。
  /// none は変換しないでそのまま返す。重い処理なので必ず別 Isolate に逃がす。
  /// プレビューは [ImageFilter.colorFilter] による GPU 描画を使い、保存時に
  /// だけこちらを呼ぶ運用。
  Future<Uint8List> apply(Uint8List bytes, ImageFilter filter) async {
    if (filter == ImageFilter.none) return bytes;
    return compute(_filterWorker, _FilterParams(bytes, filter.matrix));
  }
}

class _FilterParams {
  const _FilterParams(this.bytes, this.matrix);
  final Uint8List bytes;
  final List<double> matrix;
}

/// プレビューと同じ matrix を CPU で適用して JPEG 化する。
Uint8List _filterWorker(_FilterParams p) {
  final decoded = img.decodeImage(p.bytes);
  if (decoded == null) return p.bytes;

  final m = p.matrix;
  // RGB のみ操作（α は素通し）
  for (final px in decoded) {
    final r = px.r.toDouble();
    final g = px.g.toDouble();
    final b = px.b.toDouble();
    final nr = (m[0] * r + m[1] * g + m[2] * b + m[4]).clamp(0.0, 255.0);
    final ng = (m[5] * r + m[6] * g + m[7] * b + m[9]).clamp(0.0, 255.0);
    final nb = (m[10] * r + m[11] * g + m[12] * b + m[14]).clamp(0.0, 255.0);
    px.r = nr;
    px.g = ng;
    px.b = nb;
  }

  return Uint8List.fromList(img.encodeJpg(decoded, quality: 95));
}
