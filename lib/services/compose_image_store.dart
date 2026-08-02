import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 投稿に使う画像の置き場。
///
/// ギャラリーから選んだ画像も編集後の画像も、一時ディレクトリのままだと
/// OS にいつ消されるか分からず、下書きや投稿失敗の再送で参照できなくなる。
/// アプリのドキュメント領域にコピーして持ち、参照されなくなったものだけを
/// 後から掃除する。
class ComposeImageStore {
  ComposeImageStore._();
  static final instance = ComposeImageStore._();

  static const _dirName = 'compose_images';

  @visibleForTesting
  Directory? dirOverride;

  Future<Directory> _dir() async {
    if (dirOverride != null) return dirOverride!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 画像を保管領域に取り込み、そのファイルを指す [XFile] を返す。
  /// 既に保管領域にあるものはコピーせずそのまま返す。
  Future<XFile> adopt(XFile source) async {
    final dir = await _dir();
    if (source.path.startsWith(dir.path)) return source;

    final ext = _extensionOf(source.path);
    final name = 'img_${DateTime.now().microsecondsSinceEpoch}'
        '_${source.path.hashCode.toUnsigned(16).toRadixString(16)}$ext';
    final target = File('${dir.path}/$name');
    try {
      await File(source.path).copy(target.path);
      return XFile(target.path, mimeType: source.mimeType);
    } catch (e) {
      // コピーできなければ元のパスのまま使う（投稿自体は続行できる）
      debugPrint('[ComposeImageStore] 取り込みに失敗: $e');
      return source;
    }
  }

  /// 保管領域に新しいファイルを作るためのパスを払い出す（画像編集の出力先など）
  Future<String> newFilePath({String extension = '.jpg'}) async {
    final dir = await _dir();
    return '${dir.path}/img_${DateTime.now().microsecondsSinceEpoch}$extension';
  }

  /// [keepPaths] から参照されていないファイルを削除する。
  ///
  /// 下書きと、まだ終わっていない投稿ジョブが参照しているパスを渡すこと。
  /// 参照が漏れると必要な画像を消してしまうので、呼び出し側で漏れなく集める。
  Future<int> cleanup(Set<String> keepPaths) async {
    try {
      final dir = await _dir();
      if (!dir.existsSync()) return 0;
      final keep = keepPaths.map(_normalize).toSet();
      var removed = 0;
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (keep.contains(_normalize(entity.path))) continue;
        try {
          entity.deleteSync();
          removed++;
        } catch (_) {}
      }
      if (removed > 0) {
        debugPrint('[ComposeImageStore] 未参照の画像を $removed 件削除');
      }
      return removed;
    } catch (e) {
      debugPrint('[ComposeImageStore] 掃除に失敗: $e');
      return 0;
    }
  }

  /// 保管領域の合計サイズ
  Future<int> totalBytes() async {
    try {
      final dir = await _dir();
      if (!dir.existsSync()) return 0;
      var total = 0;
      for (final entity in dir.listSync()) {
        if (entity is File) total += entity.lengthSync();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Windows と Unix でセパレータが混ざるので揃えてから比較する
  static String _normalize(String path) => path.replaceAll('\\', '/');

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot < path.length - 6) return '.jpg';
    return path.substring(dot).toLowerCase();
  }
}
