import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 画像をプラットフォームのアップロード上限内に収めるサービス。
/// ファイル選択時のサイズ判定と、アップロード直前の実リサイズの両方で使う。
class ImageResizeService {
  ImageResizeService._();
  static final instance = ImageResizeService._();

  /// 各 SNS の 1 画像あたりサイズ上限（バイト）
  static const int xMaxBytes = 5 * 1024 * 1024;
  static const int blueskyMaxBytes = 2 * 1024 * 1024 - 50 * 1024; // 余裕を持って 1.95MB
  static const int maxLongEdge = 4000;

  /// 与えられたバイト列をリサイズ・再エンコードして maxBytes 以下にする。
  /// 既に小さい場合はそのまま返す。重い処理なので必ず compute で別 Isolate に逃がす。
  Future<Uint8List> resizeIfNeeded(
    Uint8List bytes, {
    required int maxBytes,
  }) async {
    if (bytes.length <= maxBytes) return bytes;
    return compute(_resizeWorker, _ResizeParams(bytes, maxBytes));
  }

  /// マジックバイトからファイル形式を推定する（拡張子に依存しない）。
  /// PNG/JPEG/GIF のみ判別。それ以外は null を返す。
  static String? detectMimeType(Uint8List bytes) {
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 &&
        bytes[3] == 0x38 && (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      return 'image/gif';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    return null;
  }

  static bool isGifBytes(Uint8List bytes) =>
      detectMimeType(bytes) == 'image/gif';
}

class _ResizeParams {
  const _ResizeParams(this.bytes, this.maxBytes);
  final Uint8List bytes;
  final int maxBytes;
}

/// Isolate で動く実作業。decode → 長辺制限 → JPEG quality を下げて再エンコード。
/// それでも入らなければ寸法を 70% ずつ縮める。
Uint8List _resizeWorker(_ResizeParams p) {
  final decoded = img.decodeImage(p.bytes);
  if (decoded == null) return p.bytes; // decode 失敗、そのまま返す

  img.Image current = decoded;
  if (current.width > ImageResizeService.maxLongEdge ||
      current.height > ImageResizeService.maxLongEdge) {
    final isPortrait = current.height >= current.width;
    current = img.copyResize(
      current,
      width: isPortrait ? null : ImageResizeService.maxLongEdge,
      height: isPortrait ? ImageResizeService.maxLongEdge : null,
      interpolation: img.Interpolation.linear,
    );
  }

  int quality = 90;
  Uint8List encoded = Uint8List.fromList(img.encodeJpg(current, quality: quality));

  while (encoded.length > p.maxBytes && quality > 40) {
    quality -= 10;
    encoded = Uint8List.fromList(img.encodeJpg(current, quality: quality));
  }

  while (encoded.length > p.maxBytes && current.width > 320) {
    current = img.copyResize(
      current,
      width: (current.width * 0.7).round(),
      interpolation: img.Interpolation.linear,
    );
    encoded = Uint8List.fromList(img.encodeJpg(current, quality: quality));
  }

  return encoded;
}
