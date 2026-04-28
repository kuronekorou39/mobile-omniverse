import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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
}

class ImageFilterService {
  ImageFilterService._();
  static final instance = ImageFilterService._();

  /// バイナリ画像にフィルタを適用して JPEG として返す。
  /// none は変換しないでそのまま返す。重い処理なので必ず別 Isolate に逃がす。
  Future<Uint8List> apply(Uint8List bytes, ImageFilter filter) async {
    if (filter == ImageFilter.none) return bytes;
    return compute(_filterWorker, _FilterParams(bytes, filter));
  }
}

class _FilterParams {
  const _FilterParams(this.bytes, this.filter);
  final Uint8List bytes;
  final ImageFilter filter;
}

Uint8List _filterWorker(_FilterParams p) {
  final decoded = img.decodeImage(p.bytes);
  if (decoded == null) return p.bytes;

  img.Image filtered;
  switch (p.filter) {
    case ImageFilter.bright:
      filtered = img.adjustColor(decoded, brightness: 1.15, contrast: 1.05);
      break;
    case ImageFilter.warm:
      filtered = img.adjustColor(decoded, saturation: 1.08);
      filtered = img.colorOffset(filtered, red: 18, green: 6, blue: -12);
      break;
    case ImageFilter.cool:
      filtered = img.adjustColor(decoded, saturation: 1.05);
      filtered = img.colorOffset(filtered, red: -12, green: -4, blue: 18);
      break;
    case ImageFilter.mono:
      filtered = img.grayscale(decoded);
      break;
    case ImageFilter.sepia:
      filtered = img.sepia(decoded);
      break;
    case ImageFilter.vivid:
      filtered = img.adjustColor(decoded, saturation: 1.4, contrast: 1.1);
      break;
    case ImageFilter.none:
      filtered = decoded;
      break;
  }

  return Uint8List.fromList(img.encodeJpg(filtered, quality: 95));
}
