/// Twitter/X 画像 CDN (pbs.twimg.com) がブラウザ以外の User-Agent を
/// 弾く場合があるため、CachedNetworkImage に渡す共通ヘッダー
const kImageHeaders = <String, String>{
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
};
