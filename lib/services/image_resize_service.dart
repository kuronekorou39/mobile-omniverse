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
