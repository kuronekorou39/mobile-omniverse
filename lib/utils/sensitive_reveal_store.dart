/// 「表示」を押したセンシティブ投稿を覚えておくストア。
///
/// 解除状態をオーバーレイの State だけで持つと、リストのスクロールで
/// State ごと捨てられ、戻ってきたときにまたモザイクに戻ってしまう。
/// 投稿 ID を State の外に置いて覚えておく。
/// アプリを再起動すると消える（永続化しない）。
class SensitiveRevealStore {
  SensitiveRevealStore._();

  /// 覚えておく件数の上限。超えたら古いものから捨てる。
  static const _maxEntries = 500;

  /// Dart の Set は挿入順を保つので、先頭が最も古い
  static final _revealed = <String>{};

  static bool isRevealed(String key) => _revealed.contains(key);

  static void reveal(String key) {
    _revealed.add(key);
    if (_revealed.length > _maxEntries) {
      _revealed.remove(_revealed.first);
    }
  }

  static void hide(String key) => _revealed.remove(key);

  /// モザイク設定を切り替えたときなど、隠し直したいとき用
  static void clear() => _revealed.clear();
}
