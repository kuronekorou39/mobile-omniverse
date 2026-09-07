/// X API のエンドポイント URL を一元管理
class XEndpoints {
  XEndpoints._();

  /// 通知バッジ数
  static const badgeCount =
      'https://x.com/i/api/2/badge_count/badge_count.json?supports_ntab_urt=1';

  /// REST 通知一覧
  static const notificationsAll = '/i/api/2/notifications/all.json';

  /// GraphQL ベース URL
  static const graphqlBase = 'https://x.com/i/api/graphql';

  /// XChat（新しい DM）の GraphQL ベース URL。
  ///
  /// 他の GraphQL と**ホストが違う**。公式クライアントは XChat だけ
  /// api.x.com に投げている。DM は 1.1 の dm/*.json から XChat に
  /// 移行済みで、旧 API には移行前のメッセージしか残っていない。
  static const xchatGraphqlBase = 'https://api.x.com/graphql';

  /// JSバンドル取得用
  static const home = 'https://x.com/home';
}
